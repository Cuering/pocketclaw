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