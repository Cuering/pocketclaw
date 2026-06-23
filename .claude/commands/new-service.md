# Command: /new-service

Scaffold a new singleton service for PocketClaw.

## Usage

```
/new-service <ServiceName>
```

Examples:
- `/new-service Notification` → `lib/services/notification_service.dart`
- `/new-service Analytics` → `lib/services/analytics_service.dart`

## What This Command Does

1. Creates `lib/services/<snake_case>_service.dart` with:
   - Singleton pattern (`static final instance`)
   - `ValueNotifier<XxxState>` for state (with a minimal state enum)
   - `init()` and `dispose()` stubs
   - Error handling skeleton

2. Prints a reminder to add the service to the init sequence in `main.dart`

## Generated Service Template

```dart
import 'package:flutter/foundation.dart';

enum ${ServiceName}State { idle, loading, error }

class ${ServiceName}Service {
  ${ServiceName}Service._();
  static final ${ServiceName}Service instance = ${ServiceName}Service._();

  final ValueNotifier<${ServiceName}State> _state =
      ValueNotifier(${ServiceName}State.idle);
  ValueListenable<${ServiceName}State> get state => _state;

  Object? _lastError;
  Object? get lastError => _lastError;

  Future<void> init() async {
    // TODO: initialize resources
  }

  // TODO: add public API methods here

  Future<void> dispose() async {
    _state.dispose();
    // TODO: clean up resources
  }
}
```

## After Generating

1. Add to `main.dart` init sequence in the correct order:
   ```dart
   await ${ServiceName}Service.instance.init();
   ```

2. Run `flutter analyze` to confirm no issues.

3. Write tests in `test/services/${snake_case}_service_test.dart`.
