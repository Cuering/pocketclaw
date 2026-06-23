# Rule: VoiceService

## State Machine

```
idle → checkingWakeWord → wokenUp → listeningCommand → thinking → speaking → idle
```

VoiceService uses plain listeners (not `ValueListenable`) — add/remove in
`initState`/`dispose`:

```dart
@override
void initState() {
  super.initState();
  VoiceService.instance.addListener(_onVoiceStateChange);
}

void _onVoiceStateChange() {
  if (!mounted) return;
  setState(() {});  // rebuild to reflect new VoiceService.instance.state
}

@override
void dispose() {
  VoiceService.instance.removeListener(_onVoiceStateChange);
  super.dispose();
}
```

## Lazy Init

Do NOT call `VoiceService.instance.init()` at app startup. Call it lazily
when the user first enables voice (onboarding or chat):

```dart
// In onboarding or first-time voice enable
await VoiceService.instance.init();
```

## Press-Hold Pattern

The only supported UX for manual capture is press-hold:

```dart
GestureDetector(
  onLongPressStart: (_) async {
    if (GemmaService.instance.state.value != GemmaState.ready) return;
    await VoiceService.instance.triggerManualVoiceCapture();
  },
  child: MicButton(),
)
```

No toggle UX (tap-to-start, tap-to-stop) — this pattern was dropped because
users forget to stop.

## Permission Denial

Always handle `SpeechToText` permission denial with a user-visible message:

```dart
final enabled = await _speechToText.initialize(
  onError: (error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Microphone permission required: ${error.errorMsg}')),
    );
  },
);
if (!enabled) {
  // show permission rationale, don't silently fail
}
```

## Never Start While Generating

Check both services before starting voice:

```dart
final canListen =
    GemmaService.instance.state.value == GemmaState.ready &&
    VoiceService.instance.state == VoiceState.idle;

if (!canListen) return;
await VoiceService.instance.triggerManualVoiceCapture();
```

## Audio + Gemma E2B

`flutter_gemma` v0.15 does not support direct audio input for the E2B model.
Voice always goes through the system STT pipeline → text → Gemma. Never pass
raw audio bytes to `GemmaService.generate()`.
