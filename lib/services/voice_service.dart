import 'dart:async';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/message.dart';
import '../models/conversation.dart';
import 'prefs_service.dart';
import 'device_actions_service.dart';
import 'chat_command_service.dart';
import 'gemma_service.dart';
import 'conversation_store.dart';

enum VoiceState {
  idle,
  checkingWakeWord,
  wokenUp,
  listeningCommand,
  thinking,
  speaking,
}

class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _continuousActive = false;
  VoiceState _state = VoiceState.idle;

  VoiceState get state => _state;
  bool get isContinuousActive => _continuousActive;

  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notify() {
    for (final l in _listeners) {
      l();
    }
  }

  Future<void> init() async {
    try {
      final available = await _speechToText.initialize(
        onError: (val) {
          debugPrint('🐾 VOICE SERVICE: STT error: $val');
          _handleSttStopped();
        },
        onStatus: (val) {
          debugPrint('🐾 VOICE SERVICE: STT status: $val');
          if (val == 'notListening' || val == 'done') {
            _handleSttStopped();
          }
        },
      );
      _speechEnabled = available;
      debugPrint('🐾 VOICE SERVICE: STT initialized, available=$available');
    } catch (e) {
      debugPrint('🐾 VOICE SERVICE: failed to init: $e');
    }
  }

  /// Toggle continuous wake-word listening based on user settings
  Future<void> syncContinuousState() async {
    final prefs = PrefsService.instance.current;
    final isResumed =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final shouldBeActive =
        prefs.overlayEnabled && prefs.continuousListening && !isResumed;

    if (shouldBeActive == _continuousActive) return;
    _continuousActive = shouldBeActive;

    debugPrint(
      '🐾 VOICE SERVICE: syncing state, active=$_continuousActive, wasResumed=$isResumed',
    );

    if (_continuousActive) {
      // Toggle WakeLock natively so CPU stays awake
      if (prefs.keepScreenAwake) {
        await DeviceActionsService.instance.setWakeLock(true);
      }
      _state = VoiceState.checkingWakeWord;
      _notify();
      await _startListeningLoop();
    } else {
      await DeviceActionsService.instance.setWakeLock(false);
      await _speechToText.stop();
      _state = VoiceState.idle;
      _notify();
    }
  }

  Future<void> _startListeningLoop() async {
    if (!_speechEnabled || !_continuousActive) return;
    if (_speechToText.isListening) return;

    try {
      debugPrint('🐾 VOICE SERVICE: starting STT loop for state=$_state');
      await _speechToText.listen(
        onResult: (result) {
          _handleSpeechResult(result.recognizedWords, result.finalResult);
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        listenMode: ListenMode.dictation,
      );
    } catch (e) {
      debugPrint('🐾 VOICE SERVICE: listen call failed: $e');
      if (_continuousActive) {
        Future.delayed(const Duration(seconds: 1), _startListeningLoop);
      }
    }
  }

  void _handleSttStopped() {
    if (!_continuousActive) return;
    // Auto-restart loop if continuous is enabled and we are not thinking/speaking
    if (_state == VoiceState.checkingWakeWord ||
        _state == VoiceState.listeningCommand) {
      Future.delayed(const Duration(milliseconds: 300), _startListeningLoop);
    }
  }

  Future<void> _handleSpeechResult(String words, bool isFinal) async {
    final trimmed = words.trim();
    if (trimmed.isEmpty) return;

    debugPrint('🐾 VOICE SERVICE: speech input: "$trimmed" (final=$isFinal)');

    if (_state == VoiceState.checkingWakeWord) {
      final lower = trimmed.toLowerCase();
      if (lower.contains('hey pc') ||
          lower.contains('hey computer') ||
          lower.contains('hey claw') ||
          lower.contains('claw') ||
          lower.contains('pc')) {
        debugPrint('🐾 VOICE SERVICE: Wake Word detected!');
        await _speechToText.stop();
        _state = VoiceState.wokenUp;
        _notify();

        // 1. Wake up overlay
        _sendToOverlay({'command': 'wake_up'});

        // 2. Wait a split second, start capturing command
        await Future<void>.delayed(const Duration(milliseconds: 300));
        _state = VoiceState.listeningCommand;
        _notify();
        await _startListeningLoop();
      }
    } else if (_state == VoiceState.listeningCommand) {
      // Stream real-time transcription to overlay
      _sendToOverlay({'command': 'transcription', 'text': trimmed});

      if (isFinal) {
        debugPrint('🐾 VOICE SERVICE: Final command captured: "$trimmed"');
        await _speechToText.stop();
        _state = VoiceState.thinking;
        _notify();

        _sendToOverlay({'command': 'thinking'});
        await _processCommand(trimmed);
      }
    }
  }

  Future<void> _processCommand(String commandText) async {
    try {
      debugPrint('🐾 VOICE SERVICE: processing command: "$commandText"');

      // 1. Parse via Gemma Offline Function Extraction
      final executionReport = await ChatCommandService.instance
          .tryHandleWithGemma(commandText);

      String reply;
      if (executionReport != null) {
        reply = executionReport;
      } else {
        // Fall back to normal Gemma dialogue
        final now = DateTime.now();
        final localContext =
            'Today is ${now.day}/${now.month}/${now.year}. Standard time: ${now.hour}:${now.minute}. '
            'The user asked you a voice command outside the app. Give a brief, direct answer (under 2 sentences) suitable for a voice readout.';

        reply = await GemmaService.instance.generate(
          '$localContext\n\nUser request: "$commandText"',
          userName: PrefsService.instance.current.name,
        );
      }

      // 2. Persist the voice turn in active/latest chat history!
      await _persistVoiceTurn(commandText, reply);

      // 3. Send final reply to overlay to display
      _sendToOverlay({'command': 'response', 'text': reply});
      _state = VoiceState.speaking;
      _notify();

      // 4. Leave visible for 5 seconds before returning to idle
      await Future<void>.delayed(const Duration(seconds: 5));
      _sendToOverlay({'command': 'done'});

      _state = VoiceState.checkingWakeWord;
      _notify();
      _handleSttStopped();
    } catch (e, stack) {
      debugPrint('🐾 VOICE SERVICE: process failed: $e\n$stack');
      _sendToOverlay({
        'command': 'response',
        'text': 'Sorry, something went wrong offline.',
      });
      await Future<void>.delayed(const Duration(seconds: 4));
      _sendToOverlay({'command': 'done'});
      _state = VoiceState.checkingWakeWord;
      _notify();
      _handleSttStopped();
    }
  }

  Future<void> _persistVoiceTurn(String userText, String assistantText) async {
    try {
      final allConvs = await ConversationStore.instance.loadAll();
      Conversation target;
      if (allConvs.isNotEmpty) {
        target = allConvs.first;
      } else {
        target = Conversation(title: 'Voice Session');
      }

      target.messages.add(Message(role: MessageRole.user, text: userText));
      target.messages.add(
        Message(role: MessageRole.assistant, text: assistantText),
      );

      if (target.title == 'New chat') {
        target.title = target.deriveTitleFromMessages();
      }

      await ConversationStore.instance.save(target);
      debugPrint(
        '🐾 VOICE SERVICE: Persisted overlay voice interaction in Hive chat "${target.title}"',
      );
    } catch (e) {
      debugPrint('🐾 VOICE SERVICE: failed to save turn to Hive: $e');
    }
  }

  void _sendToOverlay(Map<String, Object?> event) {
    final port = IsolateNameServer.lookupPortByName('pocketclaw_overlay_port');
    if (port != null) {
      port.send({...event, 'ts': DateTime.now().millisecondsSinceEpoch});
    } else {
      debugPrint(
        '🐾 VOICE SERVICE: overlay port not found (overlay not active)',
      );
    }
  }

  /// Trigger voice recognition immediately (manual overlay microphone button)
  Future<void> triggerManualVoiceCapture() async {
    try {
      await init();
      await _speechToText.stop();
      _state = VoiceState.wokenUp;
      _notify();
      _sendToOverlay({'command': 'wake_up'});
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _state = VoiceState.listeningCommand;
      _notify();

      final prefs = PrefsService.instance.current;
      if (prefs.keepScreenAwake) {
        await DeviceActionsService.instance.setWakeLock(true);
      }

      await _startListeningLoop();
    } catch (e) {
      debugPrint('🐾 VOICE SERVICE: manual trigger failed: $e');
    }
  }
}
