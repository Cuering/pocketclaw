import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'device_actions_service.dart';
import 'gemma_service.dart';
import 'skill_engine/skill_engine.dart';
import 'workflow_engine/workflow_engine.dart';
import 'background_task_engine/background_task_engine.dart';

class ChatCommandService {
  ChatCommandService._();
  static final ChatCommandService instance = ChatCommandService._();

  /// Evolved offline semantic intent classifier and parameter extractor.
  /// First checks standard fast-path triggers, then utilizes local Gemma inference.
  Future<String?> tryHandleWithGemma(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // 0a. Workflow execution: "run workflow X" / "execute workflow X" / "launch workflow X"
    final runWfMatch = RegExp(
      r'^(?:run|execute|launch) workflow\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (runWfMatch != null) {
      final name = runWfMatch.group(1)!.trim();
      return await _runWorkflowByName(name);
    }

    // 0b. Workflow generation: "create workflow: X" / "new workflow: X"
    final createWfMatch = RegExp(
      r'^(?:create workflow|new workflow)[:\s]+(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (createWfMatch != null) {
      final description = createWfMatch.group(1)!.trim();
      return await _createWorkflowFromCommand(description);
    }

    // 0c. Skill execution: "run skill X" / "execute skill X" / "use skill X" / "launch skill X"
    final runMatch = RegExp(
      r'^(?:run|execute|use|launch) skill\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (runMatch != null) {
      final skillName = runMatch.group(1)!.trim();
      return await _runSkillByName(skillName);
    }

    // 0d. Skill generation: "create skill: X" / "make skill: X" / "new skill: X"
    final createMatch = RegExp(
      r'^(?:create skill|make skill|new skill)[:\s]+(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (createMatch != null) {
      final description = createMatch.group(1)!.trim();
      return await _createSkillFromCommand(description);
    }

    // 1. Try fast-path regex matches first for instantaneous speed
    final fastResult = await tryHandle(trimmed);
    if (fastResult != null) {
      debugPrint('🐾 COMMANDS: Fast-path command matched for: "$trimmed"');
      return fastResult;
    }

    // 2. Fall back to local Gemma semantic JSON extraction
    try {
      debugPrint(
        '🐾 COMMANDS: running local Gemma semantic parser for: "$trimmed"',
      );
      final prompt =
          '''
You are a hardware command extractor. Map the user's request to a JSON function call.
If it matches none of these, output {"action": "none"}.

Supported actions:
1. "setTorch" args: {"enabled": bool} (e.g. "turn flashlight on", "disable torch", "light up")
2. "openDialer" args: {"phone": "string"} (e.g. "call 9876543210", "dial mom", "phone 123")
3. "openSms" args: {"phone": "string", "body": "string"} (e.g. "text john saying hello", "send message to 555: on my way")
4. "openCalendar" args: {"title": "string", "notes": "string"} (e.g. "add to calendar buy groceries", "remind me to meet mom")
5. "openAlarm" args: {"label": "string", "hour": int (0-23), "minute": int (0-59)} (e.g. "set alarm at 7:30 AM", "alarm for wake up at 8:00")
6. "openLocationSettings" args: {} (e.g. "enable gps", "location settings", "gps on")
7. "openWebSearch" args: {"query": "string"} (e.g. "search the web for weather", "google pocketclaw")
8. "sendNotification" args: {"title": "string", "body": "string"} (e.g. "send me a notification hello", "notify me to drink water")

User Request: "$trimmed"

Output EXACTLY the JSON object and absolutely nothing else. No markdown wraps, no extra text.
''';

      final response = await GemmaService.instance.generate(prompt);

      // Clean possible markdown formatting
      final cleanJson = response
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final parsed = jsonDecode(cleanJson) as Map<String, dynamic>;
      final action = parsed['action'] as String?;
      final args = parsed['args'] as Map<String, dynamic>? ?? {};

      debugPrint('🐾 COMMANDS: Gemma parsed action="$action", args=$args');

      if (action == 'setTorch') {
        final enabled = args['enabled'] as bool? ?? false;
        final res = await DeviceActionsService.instance.setTorch(enabled);
        return '🔦 ${res.message}';
      } else if (action == 'openDialer') {
        final phone = args['phone'] as String? ?? '';
        final res = await DeviceActionsService.instance.openDialer(phone);
        return '📞 ${res.message}';
      } else if (action == 'openSms') {
        final phone = args['phone'] as String? ?? '';
        final body = args['body'] as String? ?? '';
        final res = await DeviceActionsService.instance.openSms(phone, body);
        return '💬 ${res.message}';
      } else if (action == 'openCalendar') {
        final title = args['title'] as String? ?? 'PocketClaw reminder';
        final notes = args['notes'] as String? ?? '';
        final res = await DeviceActionsService.instance.openCalendar(
          title: title,
          notes: notes,
        );
        return '📅 ${res.message}';
      } else if (action == 'openAlarm') {
        final label = args['label'] as String? ?? 'PocketClaw alarm';
        final hour = args['hour'] as int?;
        final minute = args['minute'] as int?;
        final res = await DeviceActionsService.instance.openAlarm(
          label: label,
          hour: hour,
          minute: minute,
        );
        return '⏰ ${res.message}';
      } else if (action == 'openLocationSettings') {
        final res = await DeviceActionsService.instance.openLocationSettings();
        return '📍 ${res.message}';
      } else if (action == 'openWebSearch') {
        final query = args['query'] as String? ?? '';
        final res = await DeviceActionsService.instance.openWebSearch(query);
        return '🌐 ${res.message}';
      } else if (action == 'sendNotification') {
        final title = args['title'] as String? ?? 'PocketClaw Notification';
        final body = args['body'] as String? ?? '';

        // Check & request notification permission dynamically!
        final permissions = await DeviceActionsService.instance
            .checkAppPermissions();
        if (permissions['notifications'] != true) {
          await DeviceActionsService.instance.requestNotificationPermission();
          await Future<void>.delayed(const Duration(milliseconds: 600));
          final recheck = await DeviceActionsService.instance
              .checkAppPermissions();
          if (recheck['notifications'] != true) {
            return '🔔 Notification blocked. Please enable notifications to receive this alert.';
          }
        }

        final res = await DeviceActionsService.instance.sendNotification(
          title,
          body,
        );
        return '🔔 ${res.message}';
      }
    } catch (e) {
      debugPrint('🐾 COMMANDS: local Gemma parsing failed: $e');
    }
    return null;
  }

  Future<String?> tryHandle(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();

    if (_containsAny(lower, [
      'turn on flashlight',
      'flashlight on',
      'torch on',
    ])) {
      final result = await DeviceActionsService.instance.setTorch(true);
      return result.message;
    }
    if (_containsAny(lower, [
      'turn off flashlight',
      'flashlight off',
      'torch off',
    ])) {
      final result = await DeviceActionsService.instance.setTorch(false);
      return result.message;
    }
    if (_containsAny(lower, [
      'turn on gps',
      'enable gps',
      'location settings',
    ])) {
      final result = await DeviceActionsService.instance.openLocationSettings();
      return result.message;
    }
    if (lower.startsWith('call ')) {
      final phone = trimmed.substring(5).trim();
      if (phone.isEmpty) return 'Tell me the number or contact name to call.';
      final result = await DeviceActionsService.instance.openDialer(phone);
      return result.message;
    }
    if (lower.startsWith('sms ') || lower.startsWith('text ')) {
      final body = trimmed.substring(lower.startsWith('sms ') ? 4 : 5).trim();
      final result = await DeviceActionsService.instance.openSms('', body);
      return result.message;
    }
    if (_containsAny(lower, ['add to calendar', 'calendar event'])) {
      final result = await DeviceActionsService.instance.openCalendar(
        title: _stripCommand(trimmed, ['add to calendar', 'calendar event']),
      );
      return result.message;
    }
    if (_containsAny(lower, ['set alarm', 'add alarm'])) {
      final result = await DeviceActionsService.instance.openAlarm(
        label: _stripCommand(trimmed, ['set alarm', 'add alarm']),
      );
      return result.message;
    }
    return null;
  }

  bool _containsAny(String value, List<String> needles) =>
      needles.any(value.contains);

  String _stripCommand(String value, List<String> prefixes) {
    var result = value.trim();
    final lower = result.toLowerCase();
    for (final prefix in prefixes) {
      if (lower.startsWith(prefix)) {
        result = result.substring(prefix.length).trim();
        break;
      }
    }
    return result.isEmpty ? 'PocketClaw reminder' : result;
  }

  Future<String?> _runSkillByName(String nameQuery) async {
    final skills = SkillEngine.instance.list();
    if (skills.isEmpty) {
      return 'No skills saved. Say "create skill: [description]" to make one.';
    }

    final lower = nameQuery.toLowerCase();
    final match = skills.firstWhere(
      (s) => s.name.toLowerCase().contains(lower),
      orElse: () => skills.firstWhere(
        (s) => lower.contains(s.name.toLowerCase()),
        orElse: () => skills.first, // fallback — will return not-found below
      ),
    );

    // Verify we found a real match (not just fallback)
    final isRealMatch =
        match.name.toLowerCase().contains(lower) ||
        lower.contains(match.name.toLowerCase());
    if (!isRealMatch) {
      return "No skill named '$nameQuery' found. Available: ${skills.map((s) => s.name).join(', ')}.";
    }

    return await SkillEngine.instance.execute(match.id);
  }

  Future<String?> _createSkillFromCommand(String description) async {
    final skill = await SkillEngine.instance.generate(description);
    if (skill == null) {
      return 'Could not generate skill. Try a clearer description.';
    }
    return '✅ Skill "${skill.name}" created with ${skill.steps.length} step${skill.steps.length == 1 ? '' : 's'}.';
  }

  Future<String?> _runWorkflowByName(String nameQuery) async {
    final workflows = WorkflowEngine.instance.list();
    if (workflows.isEmpty) {
      return 'No workflows saved. Say "create workflow: [description]" to make one.';
    }

    final lower = nameQuery.toLowerCase();
    final match = workflows.firstWhere(
      (w) => w.name.toLowerCase().contains(lower),
      orElse: () => workflows.firstWhere(
        (w) => lower.contains(w.name.toLowerCase()),
        orElse: () => workflows.first,
      ),
    );

    final isRealMatch =
        match.name.toLowerCase().contains(lower) ||
        lower.contains(match.name.toLowerCase());
    if (!isRealMatch) {
      return "No workflow named '$nameQuery' found. Available: ${workflows.map((w) => w.name).join(', ')}.";
    }

    final task = await BackgroundTaskEngine.instance.schedule(match.id);
    return task.result ?? '✅ Workflow "${match.name}" complete.';
  }

  Future<String?> _createWorkflowFromCommand(String description) async {
    final workflow = await WorkflowEngine.instance.generate(description);
    if (workflow == null) {
      return 'Could not generate workflow. Create some skills first, then try again.';
    }
    return '✅ Workflow "${workflow.name}" created with ${workflow.stepSkillIds.length} step${workflow.stepSkillIds.length == 1 ? '' : 's'}.';
  }
}
