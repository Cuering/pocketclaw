# PocketClaw — Architectural Decisions

> Settled choices. Do not re-open without a strong reason. Each entry records
> what was chosen, what was considered, and why, so future agents don't waste
> time relitigating.

## D1 — Layer-First Architecture (not feature-first)

**Choice:** `lib/screens/`, `lib/services/`, `lib/models/`, `lib/widgets/`  
**Considered:** Feature-first (`lib/features/chat/`, `lib/features/rag/`)  
**Why:** The app has 4 screens and ~10 services. Feature folders would
scatter related services (GemmaService is used by all features). Layer-first
keeps the service seam clean.  
**Implication:** Never add `lib/features/`. Keep layer folders.

## D2 — Hive + ValueListenable (not Riverpod / Provider / BLoC)

**Choice:** Hive boxes for persistence, `ValueListenable<T>` for reactivity,
`setState` for local UI state  
**Considered:** Riverpod, Provider, BLoC  
**Why:** The app was built fast for a contest. Hive's built-in
`ValueListenable<Box<T>>` covers the reactive needs. Adding a DI framework
is future scope.  
**Implication:** Never introduce Riverpod/Provider/BLoC. `ValueListenable` +
`ValueListenableBuilder` is the reactive pattern.

## D3 — Singleton Services, No DI Framework

**Choice:** `static final XxxService instance = XxxService._();`  
**Considered:** GetIt, Provider, manual constructor injection  
**Why:** Simpler for solo development, fewer files to navigate, no
registration boilerplate. Services are effectively app-scoped singletons.  
**Implication:** Never call `new XxxService()` outside the class itself.
All init/dispose happens in `main.dart`.

## D4 — Navigator.push (not go_router)

**Choice:** `Navigator.push` / `Navigator.pop` + conditional home in
`main.dart`  
**Considered:** go_router, auto_route  
**Why:** The app has 4 screens and no deep links or URL routing. go_router
adds ~2MB and significant boilerplate for no gain.  
**Implication:** Never add go_router. If deep links become needed, revisit.

## D5 — Neobrutalism Dark Theme (not Material 3 defaults)

**Choice:** Custom `PocketClawTheme` with cyan accent, ink shadows, bold
2px borders  
**Considered:** Material 3 default dark, shadcn-style  
**Why:** Contest entry, needed a distinctive aesthetic that signals
"developer tool".  
**Implication:** All colors/typography from `PocketClawTheme` tokens only.
Never use `Color(0xFF...)` inline or `TextStyle(...)` outside the theme.

## D6 — Android Only (v1)

**Choice:** Android target only  
**Considered:** iOS  
**Why:** `flutter_gemma` requires 6+ GB RAM. Contest scope was Android.
`flutter_overlay_window` is Android-only.  
**Implication:** Don't add iOS-specific code or test on iOS.

## D7 — Gemma in Main Isolate (overlay isolate scaffolded, inactive)

**Choice:** GemmaService runs in the main isolate alongside the UI  
**Considered:** Dedicated compute isolate for Gemma  
**Why:** `flutter_gemma` v0.15 manages its own threading internally. The
overlay isolate is scaffolded for the floating bubble feature but all overlay
code is commented out.  
**Implication:** Don't move Gemma to a separate user-managed isolate. Don't
uncomment overlay code without completing the `FlutterOverlayWindow`
integration.

## D8 — Services Own Error Handling; Widgets Never Catch Service Internals

**Choice:** Every service catches its own exceptions, sets its own error
state, and exposes `lastError` or returns a typed result  
**Considered:** Let widgets catch and handle  
**Why:** Keeps error logic testable and co-located with the code that can
actually recover.  
**Implication:** Widgets react to service state (e.g. `GemmaState.error`)
and show UI — they do not wrap service calls in `try/catch`.

## D9 — Tests = Commit Gate

**Choice:** `flutter test` must pass before any commit  
**Considered:** Ship fast, add tests later  
**Why:** The app handles user data (conversations, RAG documents). Regressions
in persistence or inference UX are high-impact.  
**Implication:** Never commit with failing tests. If a test becomes flaky,
fix it before committing.
