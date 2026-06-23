# PocketClaw — Errors & Resolutions

> Log failures here when they happen. Format: `## YYYY-MM-DD — Error name` then
> Symptom / Root cause / Fix / Prevention.

## 2026-05-XX — flutter_gemma Embedder URL stale enum

**Symptom:** `EmbedderType.gecko110` points to an outdated model URL; embedding
silently uses wrong weights.  
**Root cause:** The `flutter_gemma` v0.15 enum value was hardcoded to a stale
GCS path.  
**Fix:** Bypass the enum. Pass the direct HuggingFace URL in `GemmaConfig`:
```dart
static const String geckoEmbedderUrl =
    'https://huggingface.co/google/gecko-embed-110m/resolve/main/...';
```
**Prevention:** Always check the actual URL in `GemmaConfig.geckoEmbedderUrl`
before upgrading `flutter_gemma`. Never use `EmbedderType` enum values without
verifying the resolved URL first.

---

## 2026-05-XX — Audio input missing for Gemma 4 E2B

**Symptom:** No audio modality for the E2B model; `flutter_gemma` v0.15 only
exposes audio for E4B.  
**Root cause:** Model capability gap in the library version.  
**Fix:** Use Android system STT (`speech_to_text` plugin) for voice input.
Transcription feeds text into the normal Gemma chat pipeline.  
**Prevention:** Check `flutter_gemma` release notes before upgrading. Do not
pass audio bytes directly to E2B.

---

## 2026-05-XX — GemmaState.generating blocks new requests

**Symptom:** If a user sends a second message while the model is streaming, the
second call silently fails.  
**Root cause:** `GemmaService.generate()` is not re-entrant.  
**Fix:** In the UI, disable the send button and voice trigger while
`GemmaState.generating`. Check state before calling `generate()`.  
**Prevention:** Rule: Always check `GemmaService.instance.state.value ==
GemmaState.ready` before calling `generate()`. The service does NOT queue
requests.

---

## 2026-05-XX — Hive TypeAdapter registration order crash

**Symptom:** `HiveError: Cannot write, unknown type: Conversation` on cold start.  
**Root cause:** Adapters were registered after `Hive.openBox()` was called.  
**Fix:** Always register TypeAdapters before opening any box in `init()`.  
**Prevention:** Rule in `hive.md`: register adapters first, open boxes second.
