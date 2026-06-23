# Command: /new-screen

Scaffold a new Flutter screen for PocketClaw with all required boilerplate.

## Usage

```
/new-screen <ScreenName> [--stateless]
```

Examples:
- `/new-screen Settings` → `lib/screens/settings_screen.dart`
- `/new-screen DocumentViewer` → `lib/screens/document_viewer_screen.dart`
- `/new-screen About --stateless` → stateless variant

## What This Command Does

1. Creates `lib/screens/<snake_case>_screen.dart` with:
   - `StatefulWidget` (default) or `StatelessWidget` (with `--stateless`)
   - Loading / error / data states wired up
   - Proper `dispose()` override
   - Theme tokens imported
   - Screen checklist comments marking each of the 9 items

2. Creates `test/screens/<snake_case>_screen_test.dart` with:
   - Loading state test
   - Error state test
   - Data state test

## Generated Screen Template

```dart
import 'package:flutter/material.dart';
import '../core/pocketclaw_theme.dart';

class ${ScreenName}Screen extends StatefulWidget {
  const ${ScreenName}Screen({super.key});

  @override
  State<${ScreenName}Screen> createState() => _${ScreenName}ScreenState();
}

class _${ScreenName}ScreenState extends State<${ScreenName}Screen> {
  bool _isLoading = false;
  String? _error;

  // TODO: Add controllers here and dispose them below

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      // TODO: load data
      await Future.delayed(Duration.zero);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    // TODO: dispose controllers
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // [ ] const on static widgets — mark when done
    // [ ] theme tokens — mark when done
    // [ ] keyboard safety — mark when done
    // [ ] responsive layout — mark when done
    return Scaffold(
      backgroundColor: PocketClawTheme.bg,
      appBar: AppBar(title: const Text('${ScreenName}')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // [ ] loading state
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    // [ ] error state
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: PocketClawTheme.error)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    // [ ] data state + empty state if applicable
    return const Center(child: Text('${ScreenName} — TODO'));
  }
}
```

After generating, complete the TODOs and run the screen checklist.
