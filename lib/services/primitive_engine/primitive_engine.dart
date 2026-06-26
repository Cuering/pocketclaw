import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'primitive_models.dart';

class PrimitiveEngine {
  PrimitiveEngine._();
  static final PrimitiveEngine instance = PrimitiveEngine._();

  static const _channel = MethodChannel('pocketclaw/accessibility');

  final ValueNotifier<PrimitiveState> _state = ValueNotifier(
    PrimitiveState.idle,
  );
  ValueListenable<PrimitiveState> get state => _state;

  PrimitiveExecutionResult? _lastResult;
  PrimitiveExecutionResult? get lastResult => _lastResult;

  static List<PrimitiveStep> fromJson(Map<String, dynamic> json) {
    final raw = json['steps'] as List<dynamic>?;
    if (raw == null) throw ArgumentError("Missing 'steps' array");
    return raw
        .cast<Map<String, dynamic>>()
        .map(PrimitiveStep.fromJson)
        .toList();
  }

  Future<bool> isAccessibilityEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod<void>('openAccessibilitySettings');
    } on PlatformException {
      // best-effort
    }
  }

  Future<PrimitiveExecutionResult> execute(List<PrimitiveStep> steps) async {
    if (_state.value == PrimitiveState.running) {
      return const PrimitiveExecutionResult(
        ok: false,
        stepResults: [],
        errorMessage: 'Already running',
      );
    }
    _state.value = PrimitiveState.running;

    final enabled = await isAccessibilityEnabled();
    if (!enabled) {
      _state.value = PrimitiveState.idle;
      return const PrimitiveExecutionResult(
        ok: false,
        stepResults: [],
        errorMessage: 'Accessibility permission required',
      );
    }

    final results = <PrimitiveResult>[];
    for (var i = 0; i < steps.length; i++) {
      PrimitiveResult stepResult;
      try {
        stepResult = await _executeStep(steps[i]).timeout(
          const Duration(seconds: 5),
          onTimeout: () => const PrimitiveResult(ok: false, message: 'timeout'),
        );
      } on PlatformException catch (e) {
        stepResult = PrimitiveResult(
          ok: false,
          message: e.message ?? 'platform error',
        );
      }

      results.add(stepResult);
      if (!stepResult.ok) {
        final executionResult = PrimitiveExecutionResult(
          ok: false,
          stepResults: List.unmodifiable(results),
          errorMessage: stepResult.message,
          failedAtStep: i,
        );
        _lastResult = executionResult;
        _state.value = PrimitiveState.error;
        return executionResult;
      }
    }

    final executionResult = PrimitiveExecutionResult(
      ok: true,
      stepResults: List.unmodifiable(results),
    );
    _lastResult = executionResult;
    _state.value = PrimitiveState.idle;
    return executionResult;
  }

  Future<PrimitiveResult> _executeStep(PrimitiveStep step) async {
    final method = switch (step.primitive) {
      'read_screen' => 'readScreen',
      'read_clipboard' => 'readClipboard',
      'take_screenshot' => 'takeScreenshot',
      'open_app' => 'openApp',
      _ => step.primitive,
    };

    final raw = await _channel.invokeMapMethod<String, Object?>(
      method,
      step.args.isNotEmpty ? step.args : null,
    );

    final data = <String, dynamic>{};
    if (step.primitive == 'read_screen') {
      data['tree'] = raw?['tree'] as String? ?? '';
    } else if (step.primitive == 'read_clipboard') {
      data['text'] = raw?['text'] as String? ?? '';
    } else if (step.primitive == 'take_screenshot') {
      data['path'] = raw?['path'] as String? ?? '';
    }

    return PrimitiveResult(
      ok: raw?['ok'] == true,
      message: raw?['message'] as String? ?? '',
      data: data,
    );
  }
}
