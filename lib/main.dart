// lib/main.dart
//
// PocketClaw entry point + a temporary diagnostic screen for testing Gemma.
// This screen will be replaced once we have real chat UI; for now it's a
// minimal "did Gemma work?" harness.

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'services/gemma_service.dart';

// `main` is now async because flutter_gemma's setup is async.
// Dart allows `Future<void> main()` as the entry point.
Future<void> main() async {
  // Required when calling any plugin code BEFORE runApp.
  // (runApp normally does this for us, but here we need it earlier.)
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize flutter_gemma. We're not passing a HuggingFace token because
  // litert-community/gemma-4-E2B is a PUBLIC repo (no auth needed).
  // maxDownloadRetries: 10 is the default — being explicit so the next
  // person who reads this knows the retry policy.
  FlutterGemma.initialize(maxDownloadRetries: 10);

  runApp(const PocketClawApp());
}

// Root widget. `StatelessWidget` because its config never changes —
// it's just "MaterialApp with our theme." The interesting state lives below
// in the test screen.
class PocketClawApp extends StatelessWidget {
  const PocketClawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PocketClaw',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // `debugShowCheckedModeBanner: false` removes the red "DEBUG" ribbon
      // in the top-right corner. Pure cosmetics for screenshots.
      debugShowCheckedModeBanner: false,
      home: const GemmaTestScreen(),
    );
  }
}

// `StatefulWidget` because it holds mutable state: the prompt text, the
// response, lifecycle observers. The widget object itself is immutable
// (all fields `final`); state lives in `_GemmaTestScreenState` below.
class GemmaTestScreen extends StatefulWidget {
  const GemmaTestScreen({super.key});

  @override
  State<GemmaTestScreen> createState() => _GemmaTestScreenState();
}

// The `_` prefix makes this class library-private — no other file can
// instantiate it directly. Convention for State classes.
//
// `with WidgetsBindingObserver` is a MIXIN: it gives this class the methods
// of WidgetsBindingObserver without inheriting from it. Mixins are how Dart
// adds capabilities to a class. We use it to observe app lifecycle events.
class _GemmaTestScreenState extends State<GemmaTestScreen>
    with WidgetsBindingObserver {
  // Controller for the prompt text field. `late final`:
  //   `late` = "I'll initialize this before any read, but not in the
  //             constructor" — needed because we set it up in initState.
  //   `final` = once initialized, never reassigned.
  late final TextEditingController _promptController;

  // The latest response from Gemma. Mutable, so plain `String`.
  // Starts empty; updates via setState.
  String _response = '';

  // ── Lifecycle ──────────────────────────────────────────────────────────

  // `initState` runs ONCE when this State object is first created — before
  // the first `build()` call. Use it for: creating controllers, registering
  // observers, kicking off any one-time async work.
  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(
      text: 'Say hello in one short sentence.',
    );

    // Register ourselves to receive app lifecycle callbacks
    // (didChangeAppLifecycleState below).
    WidgetsBinding.instance.addObserver(this);
  }

  // `dispose` runs ONCE when this State object is removed (screen closed,
  // hot-reload, app shutdown). Use it for: tearing down what you set up
  // in initState. Forgetting to dispose controllers and observers is the
  // #1 cause of Flutter memory leaks.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _promptController.dispose();
    super.dispose();
  }

  // Called by Flutter when the app's lifecycle state changes.
  // For now we just print — we'll add model dispose/reload logic later.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ignore: avoid_print — fine for diagnostic harness.
    debugPrint('App lifecycle: $state');
  }

  // ── Button handlers ────────────────────────────────────────────────────

  // Each handler wraps the service call in try/catch and surfaces errors
  // into _response so we can SEE what failed instead of just crashing.
  //
  // `async` + `await` pattern: the handler is async, the service call is
  // awaited, and any thrown exception lands in the catch block.

  Future<void> _onInstall() async {
    try {
      await GemmaService.instance.install();
      _setResponse('Install complete.');
    } catch (e) {
      _setResponse('Install failed: $e');
    }
  }

  Future<void> _onLoad() async {
    try {
      await GemmaService.instance.load();
      _setResponse('Model loaded.');
    } catch (e) {
      _setResponse('Load failed: $e');
    }
  }

  Future<void> _onGenerate() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _setResponse('Type a prompt first.');
      return;
    }
    try {
      // Reset the response area — tokens will fill it in as they arrive.
      _setResponse('');
      // Track start time for the demo-video tokens/sec counter.
      // DateTime.now() is fine here; we don't need monotonic clock precision.
      final startedAt = DateTime.now();
      var tokenCount = 0;

      final full = await GemmaService.instance.generate(
        prompt,
        // This callback fires once per token. We append to _response and call
        // setState so the UI rebuilds. setState is cheap; doing it per-token
        // is fine for a 2B model emitting ~10-30 tokens/sec.
        onToken: (chunk) {
          if (!mounted) {
            return; // guard: widget may be gone if user navigated away
          }
          tokenCount++;
          setState(() {
            _response = '$_response$chunk';
          });
        },
      );
      // After streaming ends, append a tiny perf summary at the bottom.
      // Useful for the demo video and for tuning later. Remove before final UI.
      final elapsed = DateTime.now().difference(startedAt);
      final tps = elapsed.inMilliseconds > 0
          ? (tokenCount * 1000 / elapsed.inMilliseconds).toStringAsFixed(1)
          : '∞';
      if (mounted) {
        setState(() {
          _response =
              '$full\n\n— $tokenCount tok / ${elapsed.inSeconds}s ≈ $tps tok/s';
        });
      }
    } catch (e) {
      _setResponse('Generate failed: $e');
    }
  }

  // Helper to update _response inside setState. setState is what tells
  // Flutter "this widget changed, rebuild it." Without setState, the UI
  // wouldn't refresh even if _response changed.
  //
  // `mounted` check: if this widget was removed from the tree (e.g. user
  // navigated away while we were awaiting), calling setState would crash.
  // Always guard async setState calls with `if (mounted)`.
  void _setResponse(String text) {
    if (!mounted) return;
    setState(() => _response = text);
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PocketClaw — Gemma Test')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // State + download progress, watched reactively.
            // ValueListenableBuilder rebuilds ONLY this subtree when state changes.
            // Cleaner than wrapping the whole screen in setState.
            ValueListenableBuilder<GemmaState>(
              valueListenable: GemmaService.instance.state,
              builder: (context, state, _) {
                return Text(
                  'State: ${state.name}',
                  style: Theme.of(context).textTheme.titleMedium,
                );
              },
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<int>(
              valueListenable: GemmaService.instance.downloadProgress,
              builder: (context, progress, _) {
                // Only show a progress bar while installing.
                // `value: null` would make it indeterminate (spinning bar);
                // we want determinate with the percentage we have.
                if (progress <= 0 || progress >= 100) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(value: progress / 100),
                    const SizedBox(height: 4),
                    Text('Download: $progress%'),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
            const Divider(height: 32),

            // Three diagnostic buttons.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _onInstall,
                  child: const Text('1. Install'),
                ),
                ElevatedButton(
                  onPressed: _onLoad,
                  child: const Text('2. Load'),
                ),
                ElevatedButton(
                  onPressed: _onGenerate,
                  child: const Text('3. Generate'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Prompt input.
            TextField(
              controller: _promptController,
              decoration: const InputDecoration(
                labelText: 'Prompt',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Response display — wrapped in Expanded + scroll so long
            // outputs don't overflow.
            Text('Response:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  _response.isEmpty ? '(nothing yet)' : _response,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
