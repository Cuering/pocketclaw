// lib/main.dart
//
// PocketClaw entry point.
//
// Two isolates run inside this app:
//   - The MAIN isolate (this file's main()): hosts the chat UI and the
//     Gemma model.
//   - The OVERLAY isolate (overlayMain below): hosts the floating bubble
//     painted over other apps via FlutterOverlayWindow.
// The overlay's tap events come back through an IsolateNameServer port
// (kMainPortName) registered by ChatScreen / DiagnosticsScreen.

import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'core/pocketclaw_theme.dart';
import 'screens/chat_screen.dart';
import 'services/context_engine/context_engine.dart';
import 'services/device_actions_service.dart';
import 'services/skill_engine/skill_engine.dart';
import 'services/skill_engine/skill_store.dart';
import 'services/gemma_service.dart';
import 'services/prefs_service.dart';
import 'services/rag_service.dart';
import 'screens/onboarding_screen.dart';
import 'models/conversation.dart';
import 'services/conversation_store.dart';
import 'services/document_store.dart';
import 'services/overlay_controller_service.dart';
import 'services/workflow_engine/workflow_engine.dart';
import 'services/workflow_engine/workflow_store.dart';
import 'services/background_task_engine/background_task_engine.dart';
import 'services/background_task_engine/task_store.dart';

// Shared port name. Must match what listeners register under
// IsolateNameServer.registerPortWithName(...). The diagnostics screen
// declares its own const with the same value for use inside that file.
const String kMainPortName = 'pocketclaw_main_port';

// ─────────────────────────────────────────────────────────────────────────
// OVERLAY ISOLATE
// ─────────────────────────────────────────────────────────────────────────

/// Entry point for the OVERLAY isolate. Android launches this in a separate
/// Dart VM when FlutterOverlayWindow.showOverlay() runs. It's a complete
/// second Flutter app that paints into the floating window — it can't see
/// state or singletons from the main app's isolate.
///
/// @pragma("vm:entry-point") prevents Dart's tree-shaker from stripping
/// this function. Without it, the function would be dead-code-eliminated
/// and Android would fail to invoke it at runtime.
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: _ClawBubble()),
  );
}

/// The floating overlay itself. It runs in a separate isolate, so it only
/// sends small events back to the main app and uses simple platform actions.
class _ClawBubble extends StatefulWidget {
  const _ClawBubble();

  @override
  State<_ClawBubble> createState() => _ClawBubbleState();
}

class _ClawBubbleState extends State<_ClawBubble> {
  bool _expanded = false;
  ReceivePort? _bubbleReceivePort;

  // Voice Interaction States
  bool _listening = false;
  bool _thinking = false;
  String _statusText = 'Hey PC...';
  String? _responseSpeechText;

  @override
  void initState() {
    super.initState();
    _registerBubblePort();
  }

  @override
  void dispose() {
    _bubbleReceivePort?.close();
    IsolateNameServer.removePortNameMapping('pocketclaw_overlay_port');
    super.dispose();
  }

  void _registerBubblePort() {
    IsolateNameServer.removePortNameMapping('pocketclaw_overlay_port');
    _bubbleReceivePort = ReceivePort();
    IsolateNameServer.registerPortWithName(
      _bubbleReceivePort!.sendPort,
      'pocketclaw_overlay_port',
    );
    _bubbleReceivePort!.listen((message) {
      if (message is Map) {
        final command = message['command'] as String?;
        if (command == 'collapse') {
          _collapse();
        } else if (command == 'wake_up') {
          _expand();
          setState(() {
            _listening = true;
            _thinking = false;
            _statusText = 'Hey PC...';
            _responseSpeechText = null;
          });
        } else if (command == 'transcription') {
          setState(() {
            _listening = true;
            _statusText = message['text'] as String? ?? 'Listening...';
          });
        } else if (command == 'thinking') {
          setState(() {
            _listening = false;
            _thinking = true;
            _statusText = 'Thinking...';
          });
        } else if (command == 'response') {
          setState(() {
            _listening = false;
            _thinking = false;
            _responseSpeechText = message['text'] as String?;
            _statusText = 'Claw responded.';
          });
        } else if (command == 'done') {
          _collapse();
        }
      }
    });
  }

  Future<void> _expand() async {
    // Dynamically resize window to 300x300 first to capture a wide outside tap area
    await FlutterOverlayWindow.resizeOverlay(300, 300, true);
    setState(() => _expanded = true);
  }

  Future<void> _collapse() async {
    setState(() {
      _expanded = false;
      _listening = false;
      _thinking = false;
      _responseSpeechText = null;
    });
    // Wait for the collapse animation to finish, then shrink window back to 80x80
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await FlutterOverlayWindow.resizeOverlay(80, 80, true);
  }

  void _manualListen() {
    _send({'type': 'manual_voice_listen'});
    setState(() {
      _expanded = true;
      _listening = true;
      _thinking = false;
      _statusText = 'Listening...';
      _responseSpeechText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_expanded) {
            _collapse();
          }
        },
        child: Container(
          width: 300,
          height: 300,
          color: Colors.transparent,
          child: Center(
            child: GestureDetector(
              onTap: () {}, // Prevent taps on the bubble itself from closing it
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: _expanded ? 156 : 68,
                height: _expanded ? 156 : 68,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: PocketClawTheme.bg2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _listening
                        ? PocketClawTheme.purple
                        : _thinking
                        ? PocketClawTheme.cyan
                        : PocketClawTheme.cyan,
                    width: 3,
                  ),
                  boxShadow: const [PocketClawTheme.hardShadow],
                ),
                child: _expanded ? _buildExpanded() : _buildBubbleIcon(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBubbleIcon() {
    return InkWell(
      onTap: _manualListen,
      borderRadius: BorderRadius.circular(8),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/images/pocketclaw_icon.png',
            width: 48,
            height: 48,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded() {
    if (_listening || _thinking || _responseSpeechText != null) {
      return _voicePanel();
    }
    return _expandedPanel();
  }

  Widget _voicePanel() {
    return Column(
      children: [
        Row(
          children: [
            Icon(
              _listening
                  ? Icons.mic
                  : _thinking
                  ? Icons.psychology
                  : Icons.record_voice_over,
              color: _listening ? PocketClawTheme.purple : PocketClawTheme.cyan,
              size: 18,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _listening
                    ? 'LISTENING'
                    : _thinking
                    ? 'THINKING'
                    : 'CLAW',
                style: TextStyle(
                  color: _listening
                      ? PocketClawTheme.purple
                      : PocketClawTheme.cyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ),
            _OverlayIconButton(
              icon: Icons.close,
              tooltip: 'Close',
              onPressed: _collapse,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: PocketClawTheme.panel(
              color: PocketClawTheme.bg,
              border: _thinking ? PocketClawTheme.cyan : PocketClawTheme.purple,
              radius: 6,
              shadow: false,
            ),
            child: SingleChildScrollView(
              child: Text(
                _listening
                    ? _statusText
                    : _thinking
                    ? 'Claw is thinking offline...'
                    : _responseSpeechText ?? 'Speak your command...',
                style: const TextStyle(
                  color: PocketClawTheme.text,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
        if (_listening) ...[
          const SizedBox(height: 4),
          const LinearProgressIndicator(color: PocketClawTheme.purple),
        ] else if (_thinking) ...[
          const SizedBox(height: 4),
          const LinearProgressIndicator(color: PocketClawTheme.cyan),
        ],
      ],
    );
  }

  Widget _expandedPanel() {
    return Column(
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/images/pocketclaw_icon.png',
                width: 30,
                height: 30,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'POCKETCLAW',
                style: TextStyle(
                  color: PocketClawTheme.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ),
            _OverlayIconButton(
              icon: Icons.close,
              tooltip: 'Minimize',
              onPressed: _collapse,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _OverlayAction(
                icon: Icons.mic,
                label: 'Voice',
                onTap: _manualListen,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _OverlayAction(
                icon: Icons.chat_bubble_outline,
                label: 'Chat',
                onTap: _openApp,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _OverlayAction(
                icon: Icons.flashlight_on_outlined,
                label: 'Torch',
                onTap: () => _send({'type': 'toggle_torch'}),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _OverlayAction(
                icon: Icons.power_settings_new,
                label: 'Deactivate',
                onTap: _destroy,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openApp() async {
    _send({'type': 'open_app'});
    await _collapse();
    await DeviceActionsService.instance.openApp();
  }

  Future<void> _destroy() async {
    _send({'type': 'overlay_deactivated'});
    // Deactivate from overlay isolate context by writing false to state file
    await OverlayControllerService.instance.writeState(false);
    await FlutterOverlayWindow.closeOverlay();
  }

  void _send(Map<String, Object?> event) {
    final port = IsolateNameServer.lookupPortByName(kMainPortName);
    port?.send({...event, 'ts': DateTime.now().millisecondsSinceEpoch});
  }
}

class _OverlayAction extends StatelessWidget {
  const _OverlayAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: PocketClawTheme.panel(
          color: PocketClawTheme.bg3,
          border: PocketClawTheme.mint,
          radius: 6,
          shadow: false,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: PocketClawTheme.text, size: 16),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PocketClawTheme.text,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 30,
        height: 30,
        decoration: PocketClawTheme.panel(
          color: PocketClawTheme.bg,
          border: PocketClawTheme.error,
          radius: 6,
          shadow: false,
        ),
        child: Icon(icon, color: PocketClawTheme.text, size: 18),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// MAIN ISOLATE
// ─────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bootstrap Gemma. Auto-loads the model in the background if already
  // installed; the chat UI's banner reacts to state transitions and
  // disappears when the model is ready. ~5-10s on a Snapdragon 7s Gen 3
  // for the GPU-delegated load.
  await ConversationStore.instance.init();
  await DocumentStore.instance.init();
  await PrefsService.instance.init();
  await GemmaService.instance.init();
  // RagService.init opens the sqlite_vec store; safe before the embedder
  // is installed (retrieval will simply return empty until embedder ready).
  // ignore: discarded_futures
  RagService.instance.init();
  await ContextEngine.instance.init();
  await SkillStore.instance.init();
  await SkillEngine.instance.init();
  await WorkflowStore.instance.init();
  await WorkflowEngine.instance.init();
  await TaskStore.instance.init();
  await BackgroundTaskEngine.instance.init();
  // Returning users: kick off install + load in background. Onboarding
  // handles first-time users directly so this is a no-op for them.
  if (PrefsService.instance.isOnboarded) {
    // ignore: discarded_futures
    GemmaService.instance.resumeIfInstalled();
  }
  runApp(const PocketClawApp());
}

class PocketClawApp extends StatelessWidget {
  const PocketClawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PocketClaw',
      debugShowCheckedModeBanner: false,
      theme: PocketClawTheme.dark(),
      darkTheme: PocketClawTheme.dark(),
      home: const _RootRouter(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// ROOT ROUTER
// ─────────────────────────────────────────────────────────────────────────

/// Decides what the user sees on launch:
///   - First-time user (!isOnboarded) → OnboardingScreen
///   - Returning user with prior chats → ChatScreen with most-recent loaded
///   - Returning user, no prior chats → ChatScreen with a fresh empty conv
///
/// Stateful so we can rebuild after onboarding completes (no need to
/// restart the app).
class _RootRouter extends StatefulWidget {
  const _RootRouter();

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  bool _showOnboarding = !PrefsService.instance.isOnboarded;

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding) {
      return OnboardingScreen(
        onDone: () {
          setState(() => _showOnboarding = false);
          // After onboarding, the model is already loaded (onboarding waited
          // for state == ready before calling onDone). Returning users would
          // have done resumeIfInstalled() in main(); we don't need to do
          // anything else here.
        },
      );
    }

    return FutureBuilder<List<Conversation>>(
      future: ConversationStore.instance.loadAll(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // Brief flash while we load the list. Material splash background.
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final convs = snapshot.data!;
        // Auto-resume: most-recent conversation (loadAll sorts desc).
        final initial = convs.isNotEmpty ? convs.first : null;
        return ChatScreen(conversation: initial);
      },
    );
  }
}
