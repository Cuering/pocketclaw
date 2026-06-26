import 'dart:async';

import 'package:flutter/services.dart';

import '../primitive_engine/primitive_engine.dart';
import '../primitive_engine/primitive_models.dart';
import 'context_snapshot.dart';

class ContextEngine {
  ContextEngine._();
  static final ContextEngine instance = ContextEngine._();

  static const _channel = MethodChannel('pocketclaw/accessibility');

  /// Captures foreground app + screen tree with fallback.
  ///   Accessibility enabled  → foregroundPackage + foregroundAppName + screenTree
  ///   Accessibility disabled → all-null snapshot, accessibilityAvailable: false
  /// Never throws.
  Future<ContextSnapshot> capture() async {
    try {
      final accessible = await PrimitiveEngine.instance
          .isAccessibilityEnabled();
      if (!accessible) {
        return ContextSnapshot(
          accessibilityAvailable: false,
          capturedAt: DateTime.now(),
        );
      }

      final results = await Future.wait([
        PrimitiveEngine.instance.execute([
          const PrimitiveStep(primitive: 'read_screen'),
        ]),
        _getContext(),
      ]);

      final execResult = results[0] as PrimitiveExecutionResult;
      final contextMap = results[1] as Map<String, String?>;
      final tree = execResult.ok
          ? execResult.stepResults.first.data['tree'] as String?
          : null;

      return ContextSnapshot(
        foregroundPackage: contextMap['package'],
        foregroundAppName: contextMap['appName'],
        screenTree: tree,
        accessibilityAvailable: true,
        capturedAt: DateTime.now(),
      );
    } catch (_) {
      return ContextSnapshot(
        accessibilityAvailable: false,
        capturedAt: DateTime.now(),
      );
    }
  }

  Future<Map<String, String?>> _getContext() async {
    try {
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getContext')
          .timeout(const Duration(seconds: 3));
      if (raw == null) return {};
      return {
        'package': raw['package'] as String?,
        'appName': raw['appName'] as String?,
      };
    } on PlatformException {
      return {};
    } on TimeoutException {
      return {};
    }
  }

  /// Produces a `[Device Context]…[/Device Context]` block for Gemma.
  /// Returns empty string if snapshot has no context.
  String formatForPrompt(ContextSnapshot snapshot) {
    if (!snapshot.hasContext) return '';

    final buf = StringBuffer('[Device Context]\n');
    if (snapshot.foregroundAppName != null) {
      buf.writeln(
        'Current app: ${snapshot.foregroundAppName} (${snapshot.foregroundPackage})',
      );
    }
    if (snapshot.screenTree != null && snapshot.screenTree!.isNotEmpty) {
      buf.writeln('Screen content:\n${snapshot.screenTree}');
    }
    buf.write('[/Device Context]');
    return buf.toString();
  }
}
