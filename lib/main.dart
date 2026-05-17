// lib/main.dart
//
// PocketClaw entry point + a temporary diagnostic screen for testing Gemma.
// This screen will be replaced once we have real chat UI; for now it's a
// minimal "did Gemma work?" harness.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'services/gemma_service.dart';

// Entry point for the OVERLAY isolate. Android launches this in a separate
// Dart VM when FlutterOverlayWindow.showOverlay() runs. It's a complete
// second Flutter app that paints into the floating window — it can't see
// state or singletons from the main app's isolate.
//
// @pragma("vm:entry-point") prevents Dart's tree-shaker from stripping this
// function. Without it, the function would be dead-code-eliminated and
// Android would fail to invoke it at runtime.
@pragma("vm:entry-point")
void overlayMain() {
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: _ClawBubble()),
  );
}

// The bubble itself. Lives in the overlay isolate — keep it dumb and
// self-contained. No service calls, no shared state with the main app.
// Day 5 work: add a tap handler that sends a message back to the main
// isolate to start the screen-capture flow.
class _ClawBubble extends StatelessWidget {
  const _ClawBubble();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        // GestureDetector + behavior: opaque lets the entire 64x64 area
        // catch the tap (not just the pixels with the circle's color).
        // shareData() ships the payload across the platform channel to
        // the main app's overlayListener stream.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // debugPrint('🐾 OVERLAY: bubble tapped');
            // FlutterOverlayWindow.shareData({
            //   'type': 'bubble_tapped',
            //   'ts': DateTime.now().millisecondsSinceEpoch,
            // });
            // debugPrint('🐾 OVERLAY: shareData called');
            debugPrint(
              '🐾 OVERLAY: bubble tapped (no main-app delivery yet — Day 5 Kotlin bridge)',
            );
          },
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.indigo,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: Text('🐾', style: TextStyle(fontSize: 28)),
            ),
          ),
        ),
      ),
    );
  }
}

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
  // ImagePicker is the entry point to the gallery/camera plugin.
  // `final` because we don't replace it; `late` not needed because we
  // can initialize it inline.
  final ImagePicker _picker = ImagePicker();

  // Currently-attached image bytes. Null = no image selected.
  // Uint8List because that's what Gemma's withImage() wants and what
  // XFile.readAsBytes() returns.
  Uint8List? _imageBytes;

  // Optional human-readable filename for the thumbnail caption.
  // Helps when the user picks multiple times — they see WHICH image is
  // currently attached.
  String? _imageName;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  // `initState` runs ONCE when this State object is first created — before
  // the first `build()` call. Use it for: creating controllers, registering
  // observers, kicking off any one-time async work.
  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: '');

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
        // Pass the currently-attached image, if any. Service is fine with null.
        imageBytes: _imageBytes,
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

  // Open the system gallery and let the user pick an image. After selection
  // we read the bytes into memory and update state. setState triggers a
  // rebuild that shows the thumbnail.
  //
  // We resize aggressively (maxWidth: 1024) for two reasons:
  //   1. Saves RAM — a 12MP camera photo is ~12MB; resized it's ~200KB.
  //   2. Speeds up the vision encoder's preprocessing meaningfully.
  // Gemma's vision encoder uses a fixed patch grid internally anyway, so
  // bigger inputs don't help quality past a point.
  Future<void> _onAttachImage() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85, // 0-100, JPEG quality. 85 is the standard sweet spot.
      );

      // User cancelled the picker — file is null, we do nothing.
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return; // guard: widget gone while we awaited bytes

      setState(() {
        _imageBytes = bytes;
        _imageName = file.name;
      });
    } catch (e) {
      _setResponse('Image picker failed: $e');
    }
  }

  // Clear the attached image. Tapped from the thumbnail's X button.
  void _onClearImage() {
    setState(() {
      _imageBytes = null;
      _imageName = null;
    });
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

  // Show the floating overlay bubble. First time: requests permission,
  // which opens Android's "Display over other apps" settings page. After
  // the user toggles us on, they have to come back and tap this again.
  Future<void> _onShowOverlay() async {
    try {
      // isPermissionGranted() returns a Future<bool>. nullable on some
      // versions — coerce to false if null.
      final granted = (await FlutterOverlayWindow.isPermissionGranted());
      if (!granted) {
        // Opens system settings. Returns once the user comes back.
        // We don't get a callback for "permission granted" specifically —
        // user has to retap our button after granting.
        await FlutterOverlayWindow.requestPermission();
        if (!mounted) return;
        _setResponse(
          'Permission requested. Toggle PocketClaw on in the settings '
          'page Android just opened, then come back and tap "5. Show '
          'Overlay" again.',
        );
        return;
      }

      // Permission already granted (or just got granted on this run).
      // Show the bubble. enableDrag lets the user drag it around.
      // height/width are in pixels; the bubble widget inside is the
      // visible part, surrounded by a transparent hit area.
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        height: 100,
        width: 100,
        alignment: OverlayAlignment.centerRight,
        overlayTitle: 'PocketClaw',
        overlayContent: 'Claw is listening',
        flag: OverlayFlag.defaultFlag,
        positionGravity: PositionGravity.auto,
      );
      if (!mounted) return;
      _setResponse(
        'Overlay shown. Drag the bubble around. Try switching to another '
        'app — the bubble should stay on top. (Tap not wired yet — Day 5.)',
      );
    } catch (e) {
      _setResponse('Overlay failed: $e');
    }
  }

  // Hide the floating bubble. Useful for the demo and for clean shutdown.
  Future<void> _onHideOverlay() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
      if (!mounted) return;
      _setResponse('Overlay closed.');
    } catch (e) {
      _setResponse('Hide overlay failed: $e');
    }
  }

  // Handle a message from the overlay isolate.
  //
  // Event format: { 'type': '<event_name>', ...payload }
  // For Day 5a, we only handle 'bubble_tapped' — flash a SnackBar so we
  // can confirm the round trip works end-to-end. Day 5b adds 'capture_screen'
  // which will trigger the MediaProjection flow.
  void _onOverlayEvent(dynamic event) {
    debugPrint('🐾 MAIN: overlay event received: $event');

    // Defensive type check — `event` is typed `dynamic` because the platform
    // channel doesn't preserve Dart types. Real-world events from
    // FlutterOverlayWindow.shareData come through as Map<Object?, Object?>
    // on most Android versions.
    if (event is! Map) {
      debugPrint('Overlay event ignored (not a Map): $event');
      return;
    }
    final type = event['type'];

    switch (type) {
      case 'bubble_tapped':
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '🐾 Bubble tapped — cross-isolate comms working',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        break;
      default:
        debugPrint('Overlay event ignored (unknown type): $type');
    }
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
                ElevatedButton.icon(
                  onPressed: _onAttachImage,
                  icon: const Icon(Icons.image),
                  label: const Text('4. Attach Image'),
                ),
                ElevatedButton.icon(
                  onPressed: _onShowOverlay,
                  icon: const Icon(Icons.bubble_chart),
                  label: const Text('5. Show Overlay'),
                ),
                ElevatedButton.icon(
                  onPressed: _onHideOverlay,
                  icon: const Icon(Icons.close),
                  label: const Text('6. Hide Overlay'),
                ),
              ],
            ),
            // Thumbnail of the currently-attached image. Only rendered when
            // an image is selected (else null is returned and Flutter skips).
            // We wrap it in Padding so it has breathing room from the buttons.
            if (_imageBytes != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    // Image.memory renders raw bytes — no file path, no
                    // network fetch. Perfect for what we have in memory.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.memory(
                        _imageBytes!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _imageName ?? 'attached image',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _onClearImage,
                      tooltip: 'Remove image',
                    ),
                  ],
                ),
              ),
            ],
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
