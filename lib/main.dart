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
import 'dart:ui';

import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';
import 'screens/diagnostics_screen.dart';
import 'services/gemma_service.dart';
import 'services/conversation_store.dart';

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

/// The floating bubble itself. Lives in the overlay isolate — keep it dumb
/// and self-contained. No service calls, no shared state with the main app.
class _ClawBubble extends StatelessWidget {
  const _ClawBubble();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: _onTap,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.deepPurple,
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Center(
            child: Text('🐾', style: TextStyle(fontSize: 28)),
          ),
        ),
      ),
    );
  }

  void _onTap() {
    debugPrint('🐾 OVERLAY: bubble tapped');
    final port = IsolateNameServer.lookupPortByName(kMainPortName);
    if (port == null) {
      debugPrint('🐾 OVERLAY: no port registered, main app may not be running');
      return;
    }
    port.send({
      'type': 'bubble_tapped',
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
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
  await GemmaService.instance.init();
  runApp(const PocketClawApp());
}

class PocketClawApp extends StatelessWidget {
  const PocketClawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PocketClaw',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: Builder(
        builder: (context) {
          return ChatScreen(
            onOpenDiagnostics: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DiagnosticsScreen(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
