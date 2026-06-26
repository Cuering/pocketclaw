// lib/services/marketplace/marketplace_service.dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../skill_engine/skill_model.dart';
import '../skill_engine/skill_store.dart';
import '../workflow_engine/workflow_model.dart';
import '../workflow_engine/workflow_store.dart';
import 'pcskill_codec.dart';

/// Exports/imports `.pcskill` bundles. Export uses the system share sheet;
/// import uses the file picker. All file logic lives behind testable seams.
class MarketplaceService {
  MarketplaceService._();
  static final MarketplaceService instance = MarketplaceService._();

  Future<void> init() async {}
  Future<void> dispose() async {}

  @visibleForTesting
  Future<String?> Function()? filePickOverride;
  @visibleForTesting
  Future<void> Function(String path, String name)? shareOverride;

  int _idCounter = 0;

  String _mintSkillId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final suffix = ((ts + _idCounter++) % 99999).toString().padLeft(5, '0');
    return 'skill-$ts-$suffix';
  }

  String _mintWorkflowId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final suffix = ((ts + _idCounter++) % 99999).toString().padLeft(5, '0');
    return 'wf-$ts-$suffix';
  }

  /// Writes a temp `.pcskill` and opens the share sheet.
  Future<void> exportBundle({
    required List<SkillModel> skills,
    List<WorkflowModel> workflows = const [],
    required String suggestedName,
  }) async {
    final json = PcSkillCodec.encode(
      skills: skills,
      workflows: workflows,
      exportedAtIso: DateTime.now().toUtc().toIso8601String(),
    );
    final safe = suggestedName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final base = safe.isEmpty ? 'bundle' : safe;
    final fileName = '$base.pcskill';

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$fileName';
    await File(path).writeAsString(json);

    if (shareOverride != null) {
      await shareOverride!(path, fileName);
      return;
    }
    await Share.shareXFiles([XFile(path)], subject: fileName);
  }

  /// Opens the picker, reads the chosen file, imports it. Null if cancelled.
  Future<ImportResult?> importFromFile() async {
    final String? contents;
    if (filePickOverride != null) {
      contents = await filePickOverride!();
    } else {
      final picked = await FilePicker.pickFiles(withData: false);
      if (picked == null || picked.files.isEmpty) return null;
      final path = picked.files.single.path;
      if (path == null) return null;
      contents = await File(path).readAsString();
    }
    if (contents == null) return null;
    return importFromString(contents);
  }

  /// Testable core: decode + save skills then workflows + summarize.
  Future<ImportResult> importFromString(String contents) async {
    final plan = PcSkillCodec.decode(
      contents,
      newSkillId: _mintSkillId,
      newWorkflowId: _mintWorkflowId,
    );
    for (final s in plan.skills) {
      await SkillStore.instance.save(s);
    }
    for (final w in plan.workflows) {
      await WorkflowStore.instance.save(w);
    }
    return ImportResult(
      skillsAdded: plan.skills.length,
      workflowsAdded: plan.workflows.length,
      warnings: plan.warnings,
    );
  }
}
