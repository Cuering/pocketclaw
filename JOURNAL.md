# PocketClaw Build Journal

Building an offline, on-device Android AI assistant powered by Gemma 4 E2B.
For the [Google Gemma 4 Challenge](https://dev.to/challenges/google-gemma-2026-05-06).

---

## Day 1 — May 7-13, 2026 (effectively done May 13)

**Strategic work:**

- Signed up for the challenge. Read both prompt templates (Build + Write) end-to-end.
- Did the math on the field: every Build entry on the leaderboard ships exactly **one** thing. The 57-reaction leader is a Write post comparing a $500 GPU to a $75 Pi — not a sprawling app. Lesson: depth and clarity win, not feature count.
- Decided to enter both tracks: a focused Build, plus a Write post about the journey.

**Scope debates (the honest part):**

The original concept (PocketClaw — overlay + wake word + voice + PDFs + hardware actions + LoRA + function calling) is a 6-month product. Spent the day arguing with myself about scope. Cycle went:

1. "Just ship the killer feature: tap-the-bubble, explain-this-screen." (Too thin?)
2. "Add image attach + follow-up Q&A." (Better.)
3. "Add wake word + voice + PDF + multimodal chat." (Back to 6 months.)
4. "Add function calling for phone/SMS/calendar/flashlight/GPS." (Even more.)
5. Reality check: with 10 days left and a beginner skill level on Flutter, all of the above is impossible. 

**Final call:** rejected the contest-shippable scope. Committing to the full vision as a multi-month build, with a Write post about the journey on May 22 as the contest submission. The build keeps going past the deadline.

**Toolchain & project scaffold:**

- Flutter 3.41.5 + Dart 3.11.3 + Android SDK 36.1.0 on macOS Apple Silicon. All ✓.
- `flutter create --platforms=android --org com.pocketclaw pocketclaw` — Android-only, no iOS/web/desktop bloat.
- Confirmed default counter app runs on Android emulator (Pixel-class, API 36.1, arm64-v8a).

**Decisions I want to remember:**

- Pragmatic clean code, NOT clean architecture (no use cases, no repositories, no DI containers). Flat folder structure: `core/`, `models/`, `services/`, `screens/`, `widgets/`.
- `setState()` for state, named routes for navigation. No Provider / Riverpod / BLoC / GetX.
- One service per concern. Singletons for things that own native resources (Gemma model).
- AI autocomplete in VS Code is OFF for this project — it kept hallucinating packages (`flutter_skill: ^0.2.6` got auto-added at one point) and breaking enum syntax.

---

## Day 2 — May 13, 2026

**Configuration:**

- `flutter_gemma: ^0.15.0` (released 13 hours before I added it — shipping fast).
- Android: `minSdk = 24` (required floor for `flutter_gemma`), `abiFilters += "arm64-v8a"` (only ABI supported by `.litertlm` engine), OpenCL libs declared as optional in manifest for GPU delegation, FOREGROUND_SERVICE + DATA_SYNC permissions for the >500 MB download path.
- `FlutterGemma.initialize(maxDownloadRetries: 10)` called in `main()` before `runApp()`. WidgetsFlutterBinding.ensureInitialized() before that. (First run forgot this — got a helpful error from the plugin.)

**Code written today (~400 lines):**

- `lib/core/constants/gemma_config.dart` — model URL, ModelType.gemma4 (not gemmaIt — Gemma 4 has different chat-template tokens), maxTokens = 2048, GPU backend.
- `lib/core/errors/app_exception.dart` — base `AppException implements Exception`, `GemmaException` subclass. Typed errors so catch blocks match on type, not error message strings.
- `lib/models/message.dart` — chat message data class with `fromJson`/`toJson`/`copyWith`/`==`. Separate from `flutter_gemma`'s internal `Message` (aliased as `fg.Message` in the service).
- `lib/services/gemma_service.dart` — singleton owning the model's full lifecycle: install / load / generate / dispose. State machine with seven states broadcast via `ValueNotifier<GemmaState>`. Download progress as a second `ValueNotifier<int>`. Every async boundary wrapped in try/catch, re-thrown as `GemmaException`.
- `lib/main.dart` — diagnostic test screen with Install / Load / Generate buttons. `ValueListenableBuilder` for the state + progress display. `WidgetsBindingObserver` hooked into the State for future app-lifecycle handling.
- `test/widget_test.dart` — smoke test, asserts the screen boots with expected buttons.

**Things that worked the first time:**

- `flutter_gemma` API matched the docs cleanly.
- `ModelResponse` → `TextResponse` runtime type narrowing in `generate()`.
- `ValueListenable`-based UI updates without any third-party state library.

**Things that broke (and what I learned):**

- VS Code's AI autocomplete kept editing files behind my back. Pinning the lesson: turn off AI suggestions for any file I'm not yet able to debug myself.
- `flutter_gemma`'s `generateChatResponse()` doesn't return `String` — it returns `ModelResponse` (a union of TextResponse / FunctionCallResponse / ThinkingResponse). The analyzer caught this before runtime. **Trust the analyzer.**
- Android emulator NAT cannot sustain a 2.6 GB HTTP stream to HuggingFace's CDN. Got to 43%, connection dropped, plugin auto-retried, restarted from 0% (HuggingFace's xet-bridge CDN doesn't honor range resumes consistently). Burned ~5 GB of office WiFi data before realizing.
- Tried to push the file directly into the app sandbox via `adb push` → blocked by Android scoped storage. Then `cp` via `run-as` → mysterious "Permission denied." Then `cat > file` redirect through `adb shell run-as` → also denied. Eventually `cat | adb shell run-as tee` worked. Verified SHA256 — byte-perfect copy on the emulator at the right path.
- Modified `GemmaService.install()` to support a `localPath` parameter via `.fromFile()`. Install succeeded. Then load failed with: `"is a LiteRT-LM model — it should be handled by Dart FFI (LiteRtLmFfiClient), not by EngineFactory."` — **this is a plugin bug**: the `.fromFile()` path on Android doesn't set the metadata that tells the runtime to use the FFI engine for `.litertlm` files. Reverted the change.

**What I now know about my dev environment:**

- The Android emulator is a useful UI testing tool and a terrible Gemma runtime: NAT can't sustain large downloads, RAM ceiling (~2 GB) won't fit a 2.5 GB model anyway. Real device is mandatory for everything beyond UI work.
- The Nord CE 4 will be the dev device — 8 GB RAM, Snapdragon 7s Gen 3, plenty for Gemma 4 E2B. USB debugging connection still TBD; that's Day 3's first task.

**End-of-day state:**

✅ Project scaffold + repo committed
✅ Android config correct for `flutter_gemma`
✅ Service layer + UI test harness complete
✅ Smoke test passing
✅ Plugin install path verified end-to-end via `.fromNetwork()` (download proven to start correctly; only the emulator's networking was the bottleneck)
⏭ Tomorrow (Day 3): get the Nord USB connection working, run on real hardware, first actual Gemma response.

---

---

## Day 2 — End of day (May 14, 8:30 PM IST)

### Wins (the journey)

- Got the Nord CE 4 USB connection working — real hardware in the loop.
- Model successfully downloaded over real WiFi to the Nord: full 2.4 GB,
  100%, plugin marked it as active. **That alone was a huge step up** from
  the emulator path where the same download had failed three times to
  NAT-related timeouts. Real device = real network = it just worked.
- Eventually identified, isolated, and fixed the `load()` routing bug.
- First-ever Gemma 4 E2B response on a real Android device from this app.

### The actual bug

`FlutterGemma.installModel()` defaults its `fileType` parameter to
`ModelFileType.task`. We were installing a `.litertlm` file without
explicitly passing `fileType: ModelFileType.litertlm`, so the plugin's
internal metadata mis-labeled the model. On `load()`, that metadata
routed the file to the Kotlin `EngineFactory` (which is for `.task`
files), and that factory threw because the bytes were obviously a
LiteRT-LM model.

Fix: one named parameter on `installModel()`.

### What it took to find it

A *lot*. Hours. We tried — in order:

1. Multiple plugin version rollbacks (0.15.x → 0.14.x → 0.13.x). Each
   failed identically. Not a regression.
2. Different `ModelType` enum values (`gemmaIt` vs `gemma4`). No effect —
   `ModelType` is about chat templates, not file routing.
3. Switching from `.fromNetwork()` to `.fromFile()` with the file
   pre-pushed via `adb`. Sidestepped network entirely. Same error.
4. Manually pushing the file into the app sandbox via `adb shell run-as`
   + `tee`. (Side lesson: Android scoped storage + SELinux are a fence
   maze. The right cat-pipe through `run-as tee` works; `cp` through
   `run-as` doesn't.)
5. Hours of looking at hallucinated documentation. AI-summarized search
   snippets had wrong version numbers and made up API surfaces. I had
   to keep verifying versions against `~/.pub-cache/`.

The fix came from reading the plugin source code directly:

\`\`\`bash
grep -r "ModelFileType" ~/.pub-cache/hosted/pub.dev/flutter_gemma-0.15.1/lib/
\`\`\`

That single command exposed where `ModelFileType.litertlm` was consumed,
and showed `installModel()` defaulted to `.task`.

### The lesson

For library-related bugs, **read the library source on your disk before
reading anything online**. The version you have installed is the only
source of truth that matters. Web searches and docs lag, AI summaries
can be flat-out wrong, and Stack Overflow is for last week's bug, not
yours.

Full debugging playbook captured in `docs/debugging-playbook.md`.

### End-of-day state

✅ Project + commits clean on GitHub
✅ flutter_gemma 0.15.1 integrated, Gemma 4 E2B working
✅ Install / load / generate all succeed on Nord CE 4
✅ Service layer tested end-to-end with real model
⏭ Day 3: image input (multimodal Gemma), bottom-sheet chat UI, follow-up
  Q&A. With the model working, the rest is "just" Flutter UI work.

  ---

## Day 3a — May 16, evening IST (perf + system prompt)

After a 2-day gap (May 15 was a rest day), came back to find an honest
problem with the working app: short prompts felt fine but anything
that asked the model to write code or explain something at length took
literally minutes and ended in mid-sentence truncation. The `flutter_gemma`
log helpfully told the story.

### What the logs actually proved

The plugin's debug output (added to verify the routing fix from Day 2)
ended up doing double duty as a perf profiler:

- All four LiteRT-LM model graphs (decode, prefill_1024, prefill_128, verify)
  had **100% of nodes delegated to LITERT_CL** — i.e. running on the Adreno
  GPU via OpenCL. So the slowness wasn't a silent CPU fallback.
- Engine init: ~7 seconds. Normal for loading 2.4 GB and JIT-compiling shaders.
- Decode throughput: ~7-8 tokens/sec sustained on Gemma 4 E2B.
- Real cause of the "5 minute" feel: a) `maxTokens: 2048` letting the model
  write essays, b) the non-streaming `generateChatResponse()` blocking the
  UI until the entire response arrived, c) no system prompt biasing toward
  concise replies.

One small inefficiency surfaced: `libLiteRtTopKOpenClSampler.so` and
`libLiteRtTopKWebGpuSampler.so` are both missing from the APK, so the
sampler falls back to CPU even though the inference is GPU. ~10-15%
potential speedup left on the table. Documented for v2.

### Three changes

1. **Streaming**. Switched `generate()` to `generateChatResponseAsync()`
   and a callback (`onToken`) so the UI updates token-by-token. Total
   wall-clock is unchanged; perceived latency drops dramatically because
   the user sees the response forming live.
2. **`maxTokens: 2048` → 1024**. Safety net only. Worst-case wall time
   roughly cut in half. Real steering happens in the system prompt.
3. **Adaptive system prompt**. First attempt was rule-based ("1-3 short
   paragraphs, one code example not three"). It worked for the exact prompt
   I tested with, but was brittle — it would refuse to give 3 implementations
   when the user explicitly asked for 3. Rewrote to describe character
   instead of rules: "match your answer length to the question; prefer plain
   answers over preambles; never restate the question." The model adapts
   per-request now.

### Numbers, before/after

Same prompt: *"Write a Python function that reverses a string, with three
different implementations."*

|                              | Tokens | Wall time | Throughput | Output quality   |
|------------------------------|--------|-----------|------------|------------------|
| Day 2 (no streaming, no SP)  | 1001   | 139s      | 7.2 tok/s  | Truncated mid-sentence |
| 3a, first SP attempt         | 132    | 15s       | 8.3 tok/s  | Only 1 impl (wrong) |
| 3a, adaptive SP              | 256    | 29s       | 8.5 tok/s  | Clean 3 implementations |

The "first SP attempt" row is the cautionary tale: a rule-based prompt
that solved the over-talkative case but broke the "user actually wants
detail" case. The adaptive version is the one I'd ship.

### Lesson

System prompts should describe *character*, not rules. Rules collapse the
moment the user's request doesn't match the rule. Character generalizes.

### End-of-day state

✅ Streaming UI — tokens appear in real time
✅ Adaptive system prompt — model length-matches the question
✅ 7-8 tok/s sustained on Adreno GPU, on a sub-$300 phone, fully offline
⏭ Image input (multimodal Gemma 4) next.

---

## Day 3b — May 16, late evening IST (image input working)

After committing the streaming + system-prompt work, kept going and added
the multimodal pipeline. Image input → Gemma 4 vision → text response.
End-to-end on the Nord CE 4, fully offline.

### Stack added today

- `image_picker: ^1.2.2` for gallery access.
- Android manifest: `READ_MEDIA_IMAGES` (Android 13+) and
  `READ_EXTERNAL_STORAGE` (capped at SDK 32) for backward compat.
- `GemmaService.generate()` now accepts optional `Uint8List? imageBytes`
  and routes to `Message.withImage(...)` when present.
- Diagnostic screen got a 4th button (Attach Image) and a thumbnail card
  with a clear-image affordance.

### The bug I would have spent hours on without grep

First attempt: attached an image, asked "what's in this image?", model
replied *"Please provide the image."*

Image was in memory (the thumbnail was visible), `Message.withImage(...)`
was being called correctly, `flutter analyze` was clean. But the model
clearly never saw an image.

Logs showed `messageType=MessageType.text` for the multimodal message —
which looked suspicious, but reading the plugin source revealed there's
no `MessageType.image` value at all. Images are detected by the
`hasImage` getter (`imageBytes != null || images.isNotEmpty`), not by
the type enum. So `messageType=text` is *normal* for an image message;
it wasn't actually the bug.

The real bug was one grep away:

```bash
---

## Day 3b — May 16, late evening IST (image input working)

After committing the streaming + system-prompt work, kept going and added the multimodal pipeline. Image input → Gemma 4 vision → text response. End-to-end on the Nord CE 4, fully offline.

### Stack added today

- `image_picker: ^1.2.2` for gallery access.
- Android manifest: `READ_MEDIA_IMAGES` (Android 13+) and `READ_EXTERNAL_STORAGE` (capped at SDK 32) for backward compat.
- `GemmaService.generate()` now accepts optional `Uint8List? imageBytes` and routes to `Message.withImage(...)` when present.
- Diagnostic screen got a 4th button (Attach Image) and a thumbnail card with a clear-image affordance.

### The bug I would have spent hours on without grep

First attempt: attached an image, asked "what's in this image?", model replied *"Please provide the image."*

Image was in memory (the thumbnail was visible), `Message.withImage(...)` was being called correctly, `flutter analyze` was clean. But the model clearly never saw an image.

Logs showed `messageType=MessageType.text` for the multimodal message — which looked suspicious, but reading the plugin source revealed there's no `MessageType.image` value at all. Images are detected by the `hasImage` getter (`imageBytes != null || images.isNotEmpty`), not by the type enum. So `messageType=text` is *normal* for an image message; it wasn't actually the bug.

The real bug was one grep away:

    grep -rn "supportImage" ~/.pub-cache/hosted/pub.dev/flutter_gemma-0.15.1/lib/

`flutter_gemma`'s `addQueryChunk()` (both the FFI path used for `.litertlm` and the mobile path) gates image handling on a `supportImage` flag that defaults to **false**:

    if (message.hasImage && supportImage) {
      _pendingImages.add(message.imageBytes!);
    }

If you don't explicitly pass `supportImage: true` to `getActiveModel(...)`, the plugin silently strips image bytes from your message and sends only the text. The model has no way to know an image was attached, so it asks the user to provide one.

Same shape of bug as the Day-2 `ModelFileType.litertlm` issue — a default parameter that's wrong for our use case, no error, no warning, just silently degraded behavior.

### The fix

Two lines:

    // gemma_config.dart
    static const bool supportImage = true;
    static const int maxNumImages = 1;

    // gemma_service.dart — in load()
    _model = await fg.FlutterGemma.getActiveModel(
      maxTokens: GemmaConfig.maxTokens,
      preferredBackend: GemmaConfig.preferredBackend,
      supportImage: GemmaConfig.supportImage,         // ← was missing
      maxNumImages: GemmaConfig.maxNumImages,         // ← was missing
    );

Load time bumped from ~7s to ~10-12s (the vision encoder also initializes now). Inference path is otherwise unchanged. Image gets fed into the vision encoder, embeddings get prepended to the token stream, model can actually see what we sent.

After the fix: attached a photo, asked "What's in this image?", got a real description.

### Pattern recognition

This is the second time the answer was "the plugin has a `supportX` / `useX` / `xFileType` parameter that defaults to false/wrong for our case, and not setting it explicitly fails silently." Adding this rule to the debugging playbook: **when feature-X doesn't work, grep the library for 'support' + 'X', 'enable' + 'X', or 'with' + 'X' parameters.** Defaults are where silent failures hide.

### End-of-day state (~10 PM IST)

- ✅ Multimodal Gemma 4 working on real hardware, offline, on a sub-$300 phone in India
- ✅ Streaming text from image+text prompts at ~7 tok/s
- ✅ One 30-second screen recording captured for the demo video reel
- ⏭ Day 4 (May 17): floating overlay bubble via `flutter_overlay_window`. Genuinely tricky Android work — different isolate from the main app, permission flow for SYSTEM_ALERT_WINDOW. Going in fresh.


---

## Day 4 — May 17, evening IST (overlay bubble)

Goal locked at start of session: **just** the overlay bubble. No screen
capture wiring, no chat UI rework. Just: tap a button → permission flow →
draggable circle floats over WhatsApp.

We hit the goal. Cleanly, without drama, in under an hour of actual code.

### Stack

- `flutter_overlay_window: ^0.5.0`
- Manifest: `SYSTEM_ALERT_WINDOW`, `FOREGROUND_SERVICE_SPECIAL_USE`,
  + `OverlayService` registration with `foregroundServiceType="specialUse"`
- Two new top-level declarations in `lib/main.dart`:
  - `@pragma("vm:entry-point") void overlayMain()` — the second isolate's
    entry function. Without the pragma, Dart's tree-shaker would strip it.
  - `_ClawBubble` widget — a transparent Material wrapping a 64px indigo
    circle with a 🐾 placeholder glyph.
- Two diagnostic buttons (`5. Show Overlay`, `6. Hide Overlay`) + handlers
  that gate on `FlutterOverlayWindow.isPermissionGranted()` and route to
  `requestPermission()` first if needed.

### Verified

- Permission flow: tap → Android settings page → toggle ON → come back →
  re-tap → bubble appears.
- Drag works.
- Bubble persists when switching to WhatsApp.
- Hide button cleanly removes the overlay.

### What's NOT done (intentionally)

- Bubble has no tap handler yet. Tapping it currently does nothing.
- Bubble can't talk to the main app. Day 5 will wire `SendPort` between
  the two isolates.
- The 🐾 is a placeholder. Real visual identity comes with Day 6 UI work.

### Mental model worth remembering

The overlay runs in a **separate Dart isolate** from the main app. That
means:
- It cannot read `GemmaService.instance` directly.
- State, singletons, providers — none of them are shared.
- Communication is via `SendPort` message passing (Day 5).

Mistakenly treating the overlay as "just another widget in my app" is the
default mental error. It's not. It's a different program that happens to
share the same APK.

### End of day

- ✅ Bubble works end-to-end on Nord
- ✅ Permission flow works
- ⏭ Day 5: cross-isolate comms + Android screen capture (MediaProjection)

---

## Day 5 partial — May 17, evening (overlay → main-app IPC: blocked)

Goal: wire tap-the-bubble → main app reacts. Specifically, ship the foundation (one cross-isolate message landing) so tomorrow's screen-capture work has a working signal channel.

Did not land that goal tonight. Found a real, known, unfixed plugin bug that blocks the path. Here's the trace.

### What we shipped (still useful)

- `_ClawBubble` wrapped in `GestureDetector(behavior: HitTestBehavior.opaque)` — taps fire reliably in the overlay isolate, confirmed via `debugPrint`.
- `_overlayShown` flag in `_GemmaTestScreenState` for lifecycle-based detection (kept for Day 5 Kotlin work).
- Debug logging on both ends (overlay-side + main-side) — gives us a clean test harness for tomorrow.

### The bug

`flutter_overlay_window 0.5.0` exposes `FlutterOverlayWindow.shareData(data)` (called from overlay) and `FlutterOverlayWindow.overlayListener` (subscribed in main app). The Dart side wraps a `BasicMessageChannel`. The native Kotlin side is supposed to route overlay-isolate sends to the main isolate's handler.

**It doesn't.** Overlay calls `shareData(...)`. Plugin emits no error. Main app's `overlayListener.listen(...)` never fires. Verified across 8+ taps. The Kotlin routing is silently broken on Android in this version.

Issue #167 on the plugin's GitHub describes exactly this, with identical code shape. Open since August 2025. **Zero maintainer replies in 9 months.** Plus 48 other open issues on the repo. Plugin is effectively unmaintained.

### What we tried before stopping

1. Re-arranged the listener subscription order (`overlayListener` getter has a side effect of installing the message handler — we tried touching it eagerly before listening). No effect.
2. Inspected the plugin source at `~/.pub-cache/.../lib/src/overlay_window.dart`. Confirmed the Dart side is fine and the bridge depends on Kotlin behavior we can't see from Dart.
3. Considered `flutter_overlay_window_plus` (a fork). Inspected its source: `shareData` only takes `String`, `overlayListener` only emits plugin lifecycle events ("overlay_shown", "overlay_moved", "overlay_closed"). It's designed for main→overlay TextView updates, not overlay→main messaging. Wrong shape — doesn't solve our problem either.
4. Briefly considered `AppLifecycleState.resumed` as an implicit signal of bubble tap (because bringing focus back triggers it). Empirically, tapping the bubble does *not* cycle the main-app lifecycle. Only manual app foregrounding does. Dead end.

### Why I stopped (a real lesson)

It was ~7:30 PM. We'd been on this single bug for ~2 hours. The remaining options were:

- Fork the plugin's Kotlin and patch the routing (3-5 hours)
- Write our own MethodChannel + Kotlin OverlayService bridge from scratch (~2 hours)

Either is an honest fix. Neither is a 30-minute fix. Continuing past midnight on Kotlin we've never written on a contest project we already know we can ship from is the trap I've been falling into all week — "we're so close, one more thing." Tonight I noticed it and stopped.

This is also Day 4's lesson: **when a library bug isn't grep-able into a one-line fix, it's an architectural fix and deserves a fresh head.** Day 2's `ModelFileType`, Day 3b's `supportImage` — those were grep-and-add-a-parameter bugs. This is "the plugin's Android-native code doesn't do what the docs claim." Different category. Same humility required.

### Plan for tomorrow (Day 5 proper)

- Native Kotlin MethodChannel inside our own app (`com.pocketclaw.pocketclaw`)
- Overlay-side: bubble tap calls a Dart method, which invokes our own channel name
- Main-side: native code bridges to a Dart handler in the main isolate
- This replaces the broken plugin bridge entirely with code we control

Then on top of that:
- Bubble tap → main app receives a known event → tomorrow's screen-capture flow can start

### End of day

- ✅ Bubble taps fire (overlay side, confirmed)
- ❌ Bubble→main IPC not working (plugin bug, deferred to Kotlin)
- ✅ Stopped at the right time, no half-built code committed

## Day 5b — Screen capture working (with caveats) — Mon May 18 evening

### What got done
- Picked `device_screenshot 0.0.8` after vetting and rejecting `media_projection_screenshot` (pre-Android-14, ships transitively broken
  `media_projection_creator`) and `flutter_overlay_window_plus` (wrong
  architecture).
- Patched plugin's build.gradle in pub cache (missing namespace, AGP 8+).
- Patched plugin's Kotlin in pub cache to register MediaProjection.Callback
  before createVirtualDisplay (Android 14 requirement).
- Worked around plugin's void-returning `requestMediaProjection()` with a
  1500ms delay before `takeScreenshot()`.
- Verified end-to-end: tap → permission dialog → screenshot bytes in
  `_imageBytes` → thumbnail renders.

### What didn't
- Plugin can't capture twice without fresh permission grant. Each capture
  burns the MediaProjection session. Multi-capture without re-prompting
  needs a real foreground service that holds projection alive — plugin's
  service doesn't.
- Pub-cache patches are brittle. Real fix is a fork. Decision tomorrow.

### What we learned
- Three MediaProjection plugins fail on Android 14, each at a different
  layer: pre-Android-14 API (plugin 1), no callback registration
  (plugin 2), no foreground service lifecycle (plugin 3).
- Android 14 (Oct 2023) was a breaking change for MediaProjection. The
  plugin ecosystem hasn't caught up. Any fresh-this-decade Android-14
  screen capture in Flutter probably means writing the Kotlin or forking
  an existing plugin.
- Empty `Log.d` instrumentation in 13 strategic spots is what gave us the
  diagnosis. Logcat-tailing the plugin's Kotlin is the right tool for this.

### Product decisions locked this evening
- Bubble is primary. Settings page on/off. Notification is just Android
  plumbing.
- Bubble auto-shows once activated, persists across restarts via
  foreground service.
- v1 is one-shot capture per permission grant. Multi-capture is Day 6
  work (fix the plugin or fork).

### Tomorrow (Day 6)
Pick one of:
- Fork device_screenshot, fix the namespace + Android 14 callback
  + per-capture permission, point pubspec at the fork
- Write our own Kotlin MethodChannel (~150 lines, ref:
  /android/src/main/kotlin/.../MainActivity.kt)
- Ship one-shot capture as the v1 demo (user accepts re-prompting)

## Day 6 — Native Kotlin MediaProjection, hit the Android 14 wall — Mon May 19 evening

### What got done
- Wrote own ScreenCaptureService.kt (209 lines) + MainActivity MethodChannel
  + Dart wrapper. Foreground service holds MediaProjection alive, ImageReader
  with continuous listener pattern, proper Android 14 callback registration.
- Bypassed three plugin defaults that bit us along the way: intent extras to
  foreground services unreliable from onActivityResult (fix: static fields on
  service companion), `-1` sentinel collides with `Activity.RESULT_OK = -1`
  (fix: nullable `Int?`), VirtualDisplay re-creation forbidden post-Android-14.

### What didn't
- Multi-shot capture. Period.
- First capture works: real PNG of current screen, ~1.34 MB. Verified.
- Captures 2-6 from the bubble: same 1,344,416 bytes every time. The bytes
  are identical. Android 14 pauses VirtualDisplay frame production after the
  initial burst and our continuous listener never receives new frames, even
  when source apps are actively rendering.
- "Recreate VirtualDisplay" workaround: blocked with explicit
  SecurityException — Android 14 added a check forbidding multiple
  createVirtualDisplay calls on one MediaProjection instance.

### What we learned
- 7+ hours across Day 5b + Day 6 on MediaProjection. The constraint isn't a
  plugin bug or a code bug — it's OS-level Android 14 behavior that requires
  fundamentally different architecture (MediaRecorder pipeline or
  vendor-specific APIs). Multi-day engineering work, not multi-hour.
- The "I told you I couldn't write Kotlin" story died: 209 lines of
  foreground service + 100 lines of MethodChannel both compiled and ran.
  Could read plugin Kotlin to diagnose constraints. Story was wrong.

### Decision
- Abandoning live screen capture for v1. Will write a "v2 roadmap" line in
  the dev.to post and keep the Kotlin in repo for engineering depth.
- Pivot to gallery-screenshot pickup OR remove screen capture entirely.
  Talked it through Tue morning — decided to drop screen capture from v1
  entirely (system screenshots → user pastes/uploads → chat).

---

## Day 7 — Pivot, ship a real chat app — Tue May 20

### Context
After-office work, 7:38 PM start. Goal: kill the screen-capture rabbit hole
once and for all, build a real chat UI, ship multi-conversation persistence,
proper error UX, and figure out the RAG path. Hard stop midnight.

### B0 — Cleanup (8:00 PM)
- Deleted ScreenCaptureService.kt, restored MainActivity.kt to the 3-line
  default, restored AndroidManifest.xml to its committed state, removed
  the Dart screen_capture wrapper, removed `device_screenshot` from
  pubspec, cleaned every reference out of main.dart.
- Committed.

### B1 — Chat UI + autobootstrap (8:00 → 10:00 PM)
- New ChatScreen replaces the diagnostic button grid as home.
- Streaming token-by-token into assistant message bubbles via Gemma's
  onToken callback. Tokens append to the placeholder bubble in setState.
- Markdown rendering for assistant responses (flutter_markdown).
- Image attachment via image_picker, kept the Day 3b vision path working.
- Conversation memory: serialize history as plain "User: ... / Assistant: ..."
  text into the prompt each turn (Gemma chat sessions are not reusable
  per the plugin's `createChat()` semantics — workaround is fine).
- Compaction stub: drop oldest messages when char-based token estimate
  exceeds 100K (out of Gemma 4's 128K window). LLM-summarized compaction
  is a future improvement.
- max_tokens bumped 1024 → 2048. The "write a short story" test now
  completes with a period instead of mid-word truncation.
- GemmaService.init() does the right thing on boot: calls
  FlutterGemma.initialize(), then always runs install() (which is
  idempotent — skips download when file exists, but registers the
  active model spec). Then auto-loads in the background. The UI watches
  state via ValueListenable<GemmaState> and the banner disappears when
  ready. No more "install → load → generate" three-tap dance.

### Bug pattern (continued)
Three new plugin defaults bit us today, same shape as Day 2/3:
- FlutterGemma.initialize() must be called in main() before runApp.
  Not optional. Plugin throws `FlutterGemma not initialized` otherwise.
- isInstalled() returning true means "file on disk", NOT "active inference
  model set". Load fails with "No active inference model set" until
  install() is called (which calls setActiveModel internally).
- install() and load() called in parallel = two copies of 1.5GB native
  model weights allocated, phone OOMs. Added idempotency guards on both:
  if already running or already in target state, no-op.

Debugging playbook updated: every silent plugin failure = grep the
pub-cache for the relevant API + its defaults. Three for three this week.

### B2 — Multi-conversation + Hive (10:15 → 10:55 PM)
- Conversation model (id via uuid, title, List<Message>, createdAt,
  updatedAt) serialized as JSON via toJson/fromJson. Skipped Hive
  TypeAdapter codegen — JSON-in-Box is simpler and ships tonight.
- Message model extended with toJson/fromJson; image bytes go in as base64.
- ConversationStore singleton: Hive box keyed by conversation id, sorted
  by updatedAt desc on read.
- ConversationListScreen: hamburger from chat opens it, shows all stored
  conversations sorted newest-first, "+ New chat" at top, tap to switch,
  long-press to delete with confirm.
- Auto-title: first non-empty user message becomes the conversation title,
  capped 60 chars, newlines collapsed.
- Persistence verified by killing the app + reopening.
- ChatScreen now accepts an optional Conversation parameter; persists
  after every completed turn (failures snackbar, exception logged).

### B2.5 — Error UX pass (11:00 → 11:30 PM)
You called this out: "in my 6 years of IT career, we never expose raw
exceptions to users." Right. Took the project through three tiers:
- Tier 1 (prevent): send button now gated on GemmaState.ready/generating.
  "Model not loaded" exception can no longer fire from user input.
- Tier 2 (friendly): failed generates render a clean "Claw couldn't
  finish that" bubble with a Retry button. Banner during load errors:
  "Couldn't start Claw. Check your connection and try again" + Retry.
  Image-picker + Hive-save failures surface as snackbars.
- Tier 3 (logs): every exception still goes to debugPrint with full
  context for debugging. Users never see Dart class names or stack traces.

Retry plumbing: ChatScreen remembers _lastFailedText + _lastFailedImage,
the failed bubble renders an onRetry callback that re-runs _handleSend
with the same args after popping the failed pair from the conversation.

### B3 — RAG verified, design committed (11:30 PM → midnight)
- Investigated flutter_gemma's RAG support. Surprise: it ships a full
  first-party RAG stack on Android. EmbeddingModel API, sqlite3-backed
  vector store with HNSW indexing above 100 documents. Web counterpart
  uses wa-sqlite + OPFS. Same Dart API both platforms.
- Plugin's hardcoded EmbeddingModel.gecko110M URL is stale (404). The
  actual files in the litert-community repo are `Gecko_*_quant.tflite`
  with different naming. Working URL verified, public (`gated: false`).
- Tried EmbeddingGemma 300M — repo is `gated: auto`, needs HF token.
  Picked Gecko 110M for the same reason we picked litert-community's
  Gemma 4 mirror: no auth, public, symmetric story.
- Wrote docs/rag-design.md with the full Day 8 plan: extend GemmaConfig,
  RAG service singleton, chunking strategy (paragraph split, ~300
  tokens, merge tinies), retrieval-into-prompt format, file picker
  integration. Zero re-investigation needed Wednesday evening.

### What got committed
- B0: cleanup
- B1: chat UI + memory + autobootstrap (10 files, +1323/-670)
- B2: multi-conv + Hive
- B2.5: error UX
- Day 7 end: RAG design doc

### What we learned
- Scope-as-everything pattern showed up twice tonight ("Path A and Path B
  both," then "B2.5 and B3 tonight"). Both times the right answer was
  cut. Once gracefully ahead of schedule (skipping B3 code, shipping
  design doc instead). Once into a real production-quality fix you
  flagged (Tier 1+2+3 error handling).
- Best engineering note of the day came from you: "we should be knowing
  what error to show and how to present it. In my 6 years of IT career
  all I learnt is, we should be knowing what error or exception to show
  how to present it to user and what user has to do." That's the real
  production instinct showing. Captured in B2.5.
- Real Day 7 output: a multi-conversation persistent chat app with
  vision, markdown, conversation memory, autobootstrap, polished error
  UX, all running on-device on a Snapdragon 7s Gen 3. That's a
  shippable v1 even if we did nothing else.

### Day 8 — May 21, 2026 (RAG Implementation)
- **Gecko 110M Embedder Integration**: Integrated the local Gecko embedder (`Gecko_*_quant.tflite`) and tokenizer from the `litert-community` Hugging Face space. Wired up the progress listener to onboarding, providing a dual-download visual layout (Gemma 4 + Gecko).
- **SQLite-Vec Vector Store**: Initialized the on-device SQLite vector database at startup. Implemented paragraph-based token-sensitive document chunking (splitting paragraphs, merging tiny fragments under 80 characters, and splitting long segments over 1200 characters).
- **Retrieve & Rank Context Injection**: Integrated custom context retrieval into Gemma prompts. Configured a dynamic file-based retrieval fallback (uses the filename as query to extract document outlines) to handle general questions like "summarize this document."
- **Soft-Fail Strategy**: Configured the RAG pipeline to soft-fail gracefully; search retrieval issues print logs but return empty lists rather than throwing exceptions, keeping the conversation stream active.

### Day 9 — May 22, 2026 (Voice, Function Calling & Native Channels)
- **Speech-to-Text & Overlay Bridging**: Integrated offline vocal inputs with the background overlay controller, enabling the floating bubble to trigger transcription.
- **Offline Gemma Function Calling**: Created the local system semantic parser using Gemma's prompt instructions. Prompted Gemma to output structured JSON representations for hardware actions (Flashlight, Alarms, SMS, Phone Dialer, Calendar, GPS, and Web Search) with zero network dependency.
- **Kotlin Platform Channel Interceptors**: Wired native platform intents inside `MainActivity.kt` to trigger actual physical device reactions in response to the parsed Gemma tool parameters.
- **Connectivity Safeguards**: Optimized network checks to query Google DNS with dynamic fallback to Hugging Face CDN, avoiding timeout issues on slow cold-boot data connections.

### Day 10 — May 23, 2026 (Walkie-Talkie UX, System Alerts & Size Cuts)
- **Snappy Walkie-Talkie Hold-and-Release Physics**: Mixed in `SingleTickerProviderStateMixin` and added a breathing pulse animation. Holding the cyan mic scales it up snappily (Curves.easeOutBack) to 1.25x and pulses, while releasing triggers automatic message transmission.
- **Self-Healing STT State Machine**: Introduced physical touch state verification (`_isPressed`). Releasing the microphone before the native STT hardware finishes its asynchronous startup sequence immediately cancels recording safely, preventing asynchronous locking bugs.
- **Dynamic On-Demand Privacy Prompts**: Completely bypassed Camera/Storage permissions in onboarding. Integrated native permission checks and dynamic requests for the Microphone and Notification channels, popping the native dialogues only when the user triggers the voice button or a notification command.
- **Offline Local System Notifications**: Implemented Kotlin-native notification dispatch and permission re-checking. Integrated `"sendNotification"` natively in Gemma's JSON tool definitions.
- **Static Analysis Compliance**: Resolved all analyzer warnings and lints (`flutter analyze` is 100% warning-clean and compile-safe).
- **90.8MB APK Size Strip**: Exploded the 284.3MB fat release APK to inspect internal files. Identified a Gradle DSL gotcha: `abiFilters += "arm64-v8a"` only appends to the compiler defaults, compiling unused architectures (`armeabi-v7a` and `x86_64`) into the final binary. Replaced with `abiFilters.clear()` and `abiFilters.add("arm64-v8a")`, and added a `packaging { jniLibs { excludes.addAll(...) } }` block to completely strip non-arm64 native `.so` engines, bringing the final package size down to **193.5MB**.
