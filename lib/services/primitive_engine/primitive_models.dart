enum PrimitiveState { idle, running, error }

class PrimitiveStep {
  final String primitive;
  final Map<String, dynamic> args;

  const PrimitiveStep({required this.primitive, this.args = const {}});

  static const localPrimitives = {'render_component'};

  factory PrimitiveStep.fromJson(Map<String, dynamic> json) {
    final primitive = json['primitive'] as String?;
    if (primitive == null || primitive.isEmpty) {
      throw ArgumentError('Missing required field: primitive');
    }
    const supported = {
      'open_app',
      'tap',
      'type',
      'scroll',
      'swipe',
      'back',
      'read_screen',
      'read_clipboard',
      'take_screenshot',
      'render_component',
    };
    if (!supported.contains(primitive)) {
      throw ArgumentError('Unknown primitive: $primitive');
    }
    final rawArgs = json['args'];
    final args = <String, dynamic>{};
    if (rawArgs is Map) {
      args.addAll(rawArgs.cast<String, dynamic>());
    }
    _validateArgs(primitive, args);
    return PrimitiveStep(primitive: primitive, args: args);
  }

  static void _validateArgs(String primitive, Map<String, dynamic> args) {
    switch (primitive) {
      case 'open_app':
        if (args['package'] is! String) {
          throw ArgumentError("open_app requires 'package': String");
        }
      case 'tap':
        final hasSelector = args['selector'] is String;
        final hasCoords = args['x'] is int && args['y'] is int;
        if (!hasSelector && !hasCoords) {
          throw ArgumentError(
            "tap requires 'selector': String or 'x': int + 'y': int",
          );
        }
      case 'type':
        if (args['text'] is! String) {
          throw ArgumentError("type requires 'text': String");
        }
      case 'scroll':
        const dirs = {'up', 'down', 'left', 'right'};
        if (!dirs.contains(args['direction'])) {
          throw ArgumentError(
            "scroll requires 'direction': up|down|left|right",
          );
        }
      case 'swipe':
        for (final field in ['fromX', 'fromY', 'toX', 'toY']) {
          if (args[field] is! int) {
            throw ArgumentError("swipe requires '$field': int");
          }
        }
      case 'render_component':
        final spec = args['spec'];
        if (spec is! Map || spec['type'] is! String || (spec['type'] as String).isEmpty) {
          throw ArgumentError(
            "render_component requires 'spec': {'type': String, ...}",
          );
        }
    }
  }
}

class PrimitiveResult {
  final bool ok;
  final String message;
  final Map<String, dynamic> data;

  const PrimitiveResult({
    required this.ok,
    this.message = '',
    this.data = const {},
  });
}

class PrimitiveExecutionResult {
  final bool ok;
  final List<PrimitiveResult> stepResults;
  final String? errorMessage;
  final int? failedAtStep;

  const PrimitiveExecutionResult({
    required this.ok,
    required this.stepResults,
    this.errorMessage,
    this.failedAtStep,
  });
}
