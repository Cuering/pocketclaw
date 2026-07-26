// Diagnostic screen — the original button-grid for testing Gemma model
// install, load, text gen, multimodal, overlay. Kept after pivot to chat
// UI for debugging. Accessible from the chat screen's overflow menu.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
// import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:image_picker/image_picker.dart';

import '../services/gemma_service.dart';

// 分享d port name used by both isolates to find each other through
// IsolateNameServer. Mirrors the constant in main.dart.
const String kMainPortName = 'pocketclaw_main_port';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

// The `_` prefix makes this class library-private — no other file can
// instantiate it directly. Convention for State classes.
//
// `with WidgetsBindingObserver` is a MIXIN: it gives this class the methods
// of WidgetsBindingObserver without inheriting from it. Mixins are how Dart
// adds capabilities to a class. We use it to observe app lifecycle events.
class _DiagnosticsScreenState extends State<DiagnosticsScreen>
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

  // ReceivePort for messages from the overlay isolate. We register its
  // 发送Port with IsolateNameServer so the overlay can look it up by name
  // and send messages directly. This bypasses the broken shareData bridge
  // in flutter_overlay_window 0.5.0 (issue #22 in the plugin's repo).
  ReceivePort? _mainReceivePort;
  StreamSubscription<dynamic>? _mainPortSubscription;
  // ── Lifecycle ──────────────────────────────────────────────────────────

  // `initState` runs ONCE when this State object is first created — before
  // the first `build()` call. Use it for: creating controllers, registering
  // observers, kicking off any one-time async work.
  @override
  void initState() {
    super.initState();
    debugPrint('🐾 MAIN: initState');

    _promptController = TextEditingController(text: '');

    // Register ourselves to receive app lifecycle callbacks
    // (didChangeAppLifecycleState below).
    WidgetsBinding.instance.addObserver(this);
    // 去设置 the IsolateNameServer port for receiving overlay events.
    // 1. Create a new ReceivePort (it's a Stream<dynamic> of messages).
    // 2. Register its 发送Port with a known name so the overlay can find it.
    // 3. Listen for messages and dispatch to our handler.
    //
    // We unregister any previous binding first because hot restart can leave
    // a stale registration behind, which causes registerPortWithName to fail.
    IsolateNameServer.removePortNameMapping(kMainPortName);

    _mainReceivePort = ReceivePort();
    final registered = IsolateNameServer.registerPortWithName(
      _mainReceivePort!.sendPort,
      kMainPortName,
    );
    debugPrint('🐾 MAIN: registered port "$kMainPortName" = $registered');

    _mainPortSubscription = _mainReceivePort!.listen((message) {
      debugPrint('🐾 MAIN: received via ReceivePort: $message');
      _on悬浮窗Event(message);
    });
  }

  // `dispose` runs ONCE when this State object is removed (screen closed,
  // hot-reload, app shutdown). Use it for: tearing down what you set up
  // in initState. Forgetting to dispose controllers and observers is the
  // #1 cause of Flutter memory leaks.
  @override
  void dispose() {
    // 取消 subscriptions first (no more events get processed).
    _mainPortSubscription?.cancel();
    // 关闭 the ReceivePort to release native resources.
    _mainReceivePort?.close();
    // Remove the named registration so a fresh restart won't see a stale port.
    IsolateNameServer.removePortNameMapping(kMainPortName);
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

  Future<void> _on生成() async {
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
      _setResponse('生成 failed: $e');
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
  Future<void> _onShow悬浮窗() async {
    try {
      if (!mounted) return;
      _setResponse('悬浮窗 is disabled.');
    } catch (e) {
      _setResponse('悬浮窗 failed: $e');
    }
  }

  // Hide the floating bubble. Useful for the demo and for clean shutdown.
  Future<void> _onHide悬浮窗() async {
    try {
      // await Flutter悬浮窗Window.close悬浮窗();
      if (!mounted) return;
      _setResponse('悬浮窗 closed.');
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
  void _on悬浮窗Event(dynamic message) {
    debugPrint('🐾 MAIN: overlay event received: $message');
    if (!mounted) return;
    // Bubble taps currently no-op. 对话 UI will hook this up later
    // to bring the chat to foreground.
  }
  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PocketClaw — Gemma 测试')),
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
                  child: const Text('1. 安装'),
                ),
                ElevatedButton(
                  onPressed: _onLoad,
                  child: const Text('2. 加载'),
                ),
                ElevatedButton(
                  onPressed: _on生成,
                  child: const Text('3. 生成'),
                ),
                ElevatedButton.icon(
                  onPressed: _onAttachImage,
                  icon: const Icon(Icons.image),
                  label: const Text('4. 附加图片'),
                ),
                ElevatedButton.icon(
                  onPressed: _onShow悬浮窗,
                  icon: const Icon(Icons.bubble_chart),
                  label: const Text('5. 显示悬浮窗'),
                ),
                ElevatedButton.icon(
                  onPressed: _onHide悬浮窗,
                  icon: const Icon(Icons.close),
                  label: const Text('6. 隐藏悬浮窗'),
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
                      tooltip: '移除图片',
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
            Text('回复：', style: Theme.of(context).textTheme.titleMedium),
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
