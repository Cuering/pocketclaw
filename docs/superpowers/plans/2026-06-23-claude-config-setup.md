# PocketClaw Claude Config Setup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a complete `.claude/` configuration — rules, skills, commands, reviewer agent, relay docs, and CLAUDE.md — adapted to pocketclaw's actual stack (Gemma 4 E2B, RAG/Gecko, Hive, VoiceService, neobrutalism theme, singleton services, layer-first architecture).

**Architecture:** 22 markdown/JSON files written from scratch. No Dart code changes. Files fall into six groups: settings.json (1), relay docs at project root (4), CLAUDE.md (1), rules (8), skills (6), commands + agent (4). Each task ends with `flutter analyze` passing and a commit.

**Tech Stack:** Markdown, JSON, Flutter/Dart project conventions. No dependencies to install.

## Global Constraints

- No changes to any `.dart` file
- All files use LF line endings
- Exact token names used throughout: `PocketClawTheme.bg`, `bg2`, `bg3`, `cyan`, `purple`, `mint`, `text`, `text2`, `muted`, `warning`, `error`, `ink`, `hardShadow`, `hardBorder()`, `panel()`
- Exact service names: `GemmaService`, `RagService`, `VoiceService`, `DeviceActionsService`, `ChatCommandService`, `ConversationStore`, `DocumentStore`, `PrefsService`, `OverlayControllerService`
- Exact state enums: `GemmaState` (notInstalled/installing/installed/loading/ready/generating/error), `EmbedderState` (notInstalled/installing/installed/error), `RagState` (notReady/ready/indexing/retrieving/error), `VoiceState` (idle/checkingWakeWord/wokenUp/listeningCommand/thinking/speaking)
- Project owner: Manoj Shetty (personal side project, not Mobiux)
- App ID: `pocketclaw` — Android only, v1

---

## Task 1: settings.json

**Files:**
- Modify: `.claude/settings.local.json` (exists — merge, don't replace)
- Create: `.claude/settings.json`

**Interfaces:**
- Produces: auto-format hook on every Write/Edit; permission allow/deny lists used by all subsequent tasks

- [ ] **Step 1: Write `.claude/settings.json`**

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "dart format $CLAUDE_TOOL_INPUT_PATH 2>/dev/null; true"
          }
        ]
      }
    ]
  },
  "permissions": {
    "allow": [
      "Bash(flutter pub get*)",
      "Bash(flutter pub upgrade*)",
      "Bash(flutter analyze*)",
      "Bash(flutter test*)",
      "Bash(flutter run*)",
      "Bash(flutter build*)",
      "Bash(dart format*)",
      "Bash(dart fix*)",
      "Bash(dart analyze*)",
      "Bash(git diff*)",
      "Bash(git log*)",
      "Bash(git status*)",
      "Bash(git add*)",
      "Bash(git branch*)",
      "Bash(git checkout*)",
      "Bash(git fetch*)",
      "Bash(git pull*)",
      "Bash(semble*)",
      "Bash(flutter devices*)",
      "Bash(flutter doctor*)",
      "Bash(flutter pub deps*)",
      "Bash(find . -name*)",
      "Bash(grep -*)"
    ],
    "deny": [
      "Bash(git push --force*)",
      "Bash(rm -rf lib/*)",
      "Bash(flutter clean && flutter pub get && flutter run --release*)"
    ]
  }
}
```

- [ ] **Step 2: Verify `.claude/settings.local.json` is untouched**

Run: `cat .claude/settings.local.json`
Expected output: existing MCP server config still present (do NOT overwrite it).

- [ ] **Step 3: Verify flutter analyze still passes**

Run: `flutter analyze`
Expected: `No issues found!` (settings.json does not affect Dart analysis)

- [ ] **Step 4: Commit**

```bash
git add .claude/settings.json
git commit -m "chore: add .claude/settings.json with dart format hook and permissions"
```

---

## Task 2: Relay Docs (ARCHITECTURE.md, DECISIONS.md, CHANGELOG.md, ERRORS.md)

**Files:**
- Create: `ARCHITECTURE.md`
- Create: `DECISIONS.md`
- Create: `CHANGELOG.md`
- Create: `ERRORS.md`

**Interfaces:**
- Produces: four living documents referenced in CLAUDE.md's "Before every task" section

- [ ] **Step 1: Write `ARCHITECTURE.md`**

```markdown
# PocketClaw — Architecture

> Read this before starting any task. It is the system map.

## Layer Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  Screens (lib/screens/)                                      │
│  chat_screen.dart · conversation_list_screen.dart           │
│  onboarding_screen.dart · diagnostics_screen.dart           │
└───────────────────┬─────────────────────────────────────────┘
                    │ calls singleton .instance methods
┌───────────────────▼─────────────────────────────────────────┐
│  Services (lib/services/)                                    │
│  GemmaService  RagService  VoiceService                      │
│  DeviceActionsService  ChatCommandService                    │
│  ConversationStore  DocumentStore  PrefsService              │
│  OverlayControllerService  ConnectivityService               │
└──────┬────────────┬───────────────────────────┬─────────────┘
       │            │                           │
┌──────▼──────┐  ┌──▼──────────────┐  ┌────────▼────────────┐
│  Models     │  │  Hive Boxes     │  │  Native Layer       │
│  (lib/models│  │  conversations  │  │  flutter_gemma      │
│  Conversation  │  documents      │  │  speech_to_text     │
│  Document   │  │  (local SQLite) │  │  MethodChannel      │
│  Message    │  └─────────────────┘  │  pocketclaw/device  │
│  UserPrefs) │                       └─────────────────────┘
└─────────────┘
```

## Isolate Architecture

The app runs in **one active isolate** (main). A second isolate (overlay) is
scaffolded but inactive — all overlay code is commented out pending
`FlutterOverlayWindow` integration.

- **Main isolate:** UI + Gemma inference + all services
- **Overlay isolate (`overlayMain`):** Floating bubble — commented out

## Service Init Sequence (main.dart)

```dart
await ConversationStore.instance.init();   // Hive box for chats
await DocumentStore.instance.init();       // Hive box for RAG doc metadata
await PrefsService.instance.init();        // SharedPreferences wrapper
await GemmaService.instance.init();        // Detects installed/not installed
RagService.instance.init();               // sqlite-vec store (fire-and-forget)
// VoiceService init is lazy — called from onboarding or chat
```

## Key Service APIs

### GemmaService
```dart
GemmaService.instance.state           // ValueListenable<GemmaState>
GemmaService.instance.embedderState   // ValueListenable<EmbedderState>
GemmaService.instance.downloadProgress // ValueListenable<int> (0–100)
GemmaService.instance.lastError       // Object?
await GemmaService.instance.ensureInstalled()
await GemmaService.instance.ensureLoaded()
await GemmaService.instance.generate(prompt, imageBytes: bytes, onToken: cb)
await GemmaService.instance.installEmbedder()
await GemmaService.instance.getEmbedder()   // returns EmbeddingModel
await GemmaService.instance.dispose()
```

### RagService
```dart
RagService.instance.state             // ValueListenable<RagState>
await RagService.instance.indexDocument(text: t, name: n, conversationId: id)
await RagService.instance.retrieve(query: q, conversationId: id)
await RagService.instance.getDocStarts(conversationId: id)
await RagService.instance.deleteDocument(doc)
RagService.instance.chunk(text)       // List<String>
```

### VoiceService
```dart
VoiceService.instance.state           // VoiceState (not ValueListenable)
VoiceService.instance.addListener(fn)
VoiceService.instance.removeListener(fn)
await VoiceService.instance.init()
await VoiceService.instance.triggerManualVoiceCapture()
```

### DeviceActionsService
```dart
await DeviceActionsService.instance.setTorch(bool)
await DeviceActionsService.instance.openDialer(phone)
await DeviceActionsService.instance.openSms(phone, body)
await DeviceActionsService.instance.openCalendar(title: t, dateTime: dt)
await DeviceActionsService.instance.openAlarm(label: l, hour: h, minute: m)
await DeviceActionsService.instance.openWebSearch(query)
await DeviceActionsService.instance.sendNotification(title, body)
// All return DeviceActionResult(ok: bool, message: String)
```

### ChatCommandService
```dart
await ChatCommandService.instance.tryHandleWithGemma(text) // String?
await ChatCommandService.instance.tryHandle(text)          // String?
// Returns null if not a device command; returns reply string if handled
```

## Feature Inventory

| Screen | File | State source |
|---|---|---|
| Chat | `chat_screen.dart` | GemmaService + ConversationStore (ValueListenable) |
| Conversation list | `conversation_list_screen.dart` | ConversationStore |
| Onboarding | `onboarding_screen.dart` | PrefsService |
| Diagnostics | `diagnostics_screen.dart` | GemmaService + RagService state |

## Routing

Simple `Navigator` — no go_router. Entry screen determined in `main.dart`:
```dart
if (PrefsService.instance.isOnboarded) → ChatScreen
else → OnboardingScreen
```
Navigation between screens uses `Navigator.push` / `Navigator.pop`.

## Design System

`lib/core/pocketclaw_theme.dart` — neobrutalism dark theme.
Colors: `bg`, `bg2`, `bg3`, `cyan`, `purple`, `mint`, `text`, `text2`,
`muted`, `warning`, `error`, `ink`.
Shadow: `hardShadow` (5,5 offset, 0 blur, ink color).
Border: `hardBorder([color, width])` — default cyan, 2px.
Panel: `panel({color, border, radius, shadow})` — standard card decoration.
```

- [ ] **Step 2: Write `DECISIONS.md`**

```markdown
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
```

- [ ] **Step 3: Write `CHANGELOG.md`**

```markdown
# PocketClaw — Changelog

> Append-only. One entry per shipped unit of work. Format: `## YYYY-MM-DD — What shipped`

## 2026-06-23 — Claude config setup

Added `.claude/` configuration: CLAUDE.md, rules (gemma, rag, hive, services,
widgets, theme, performance, voice), skills (gemma-patterns, rag-patterns,
device-actions-patterns, screen-checklist, smart-commit, code-search-tools),
commands (new-screen, new-service, pr-review), and flutter-reviewer agent.
Relay docs added: ARCHITECTURE.md, DECISIONS.md, CHANGELOG.md, ERRORS.md.

## 2026-05-XX — Contest submission (Google Gemma 4 Challenge)

Shipped: on-device chat (Gemma 4 E2B INT4), multimodal vision (image analysis),
RAG document Q&A (Gecko 110M + sqlite-vec), device actions via natural language
(flashlight, alarms, SMS, calendar, dialer, notifications), persistent chat
history (Hive), context compaction, press-hold voice input (system STT),
neobrutalism dark theme, onboarding flow, diagnostics screen.
```

- [ ] **Step 4: Write `ERRORS.md`**

```markdown
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
```

- [ ] **Step 5: Verify flutter analyze still passes**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add ARCHITECTURE.md DECISIONS.md CHANGELOG.md ERRORS.md
git commit -m "docs: add relay docs (ARCHITECTURE, DECISIONS, CHANGELOG, ERRORS)"
```

---

## Task 3: CLAUDE.md

**Files:**
- Create: `CLAUDE.md`

**Interfaces:**
- Consumes: relay docs from Task 2 (referenced by name)
- Produces: primary instruction hub read by every agent before starting work

- [ ] **Step 1: Write `CLAUDE.md`**

```markdown
# PocketClaw — Claude Instructions

## Before EVERY Task

Read these four relay files first. They are the ground truth.

1. `ARCHITECTURE.md` — system map, service APIs, init sequence
2. `DECISIONS.md` — settled choices (don't re-open without strong reason)
3. `CHANGELOG.md` — what has shipped
4. `ERRORS.md` — known failure patterns and their fixes

---

## App Identity

- **Name:** PocketClaw
- **Owner:** Manoj Shetty (personal side project)
- **Platform:** Flutter, Android only
- **Domain:** Private, offline, on-device AI assistant
- **LLM:** Gemma 4 E2B (INT4, ~1.5 GB) via `flutter_gemma ^0.15.1`
- **Embedder:** Gecko 110M (INT8, ~110 MB) for RAG
- **Persistence:** Hive (conversations, documents, prefs)
- **Design:** Neobrutalism dark — cyan accent, ink shadows, bold borders
- **Status:** Shipped for Google Gemma 4 Challenge; roadmap in `further_plan.md`

---

## Non-Negotiables

1. **Model privacy** — GemmaService and RagService make zero network calls
   after model download. Inference is 100% on-device.
2. **Performance** — Gemma is 1.5 GB. Peak RAM ≈ 2 GB. Never block the main
   thread. Cancel `StreamSubscription` when a screen disposes.
3. **UX feel** — Neobrutalism: bold `2px` borders, flat `hardShadow`, `cyan`
   primary, `ink` background accents. Every new screen must use theme tokens.
4. **AI reliability** — Always degrade gracefully. Show a user-visible error
   when `GemmaState.error` or `RagState.error`. Never silently drop a response.
5. **Tests = commit gate** — `flutter test` must pass before any commit. No
   exceptions.
6. **Minimal scope** — Do not implement anything from the out-of-scope list
   below without an explicit feature request.

---

## Design System (`lib/core/pocketclaw_theme.dart`)

### Colors (always `PocketClawTheme.*` — never `Color(0xFF...)` inline)

| Token | Hex | Use |
|---|---|---|
| `bg` | `#0F1117` | Scaffold background |
| `bg2` | `#171923` | Card / panel background |
| `bg3` | `#212431` | Input / elevated surface |
| `cyan` | `#00E5FF` | Primary accent, borders, focus |
| `purple` | `#7C4DFF` | Secondary accent |
| `mint` | `#00FFA3` | Success / tertiary |
| `text` | `#FFFFFF` | Primary text |
| `text2` | `#B7BCCB` | Secondary text |
| `muted` | `#7D8597` | Placeholder / label |
| `warning` | `#FFD166` | Warning states |
| `error` | `#FF5D73` | Error states |
| `ink` | `#05060A` | Shadow color, button foreground |

### Shadow & Border

```dart
PocketClawTheme.hardShadow      // BoxShadow(offset: Offset(5,5), blurRadius: 0, color: ink)
PocketClawTheme.hardBorder()    // Border.all(color: cyan, width: 2)
PocketClawTheme.hardBorder(PocketClawTheme.purple, 2)  // purple variant
PocketClawTheme.panel()         // BoxDecoration: bg2 + cyan border + hardShadow + radius 8
```

### Typography

All text from `Theme.of(context).textTheme.*`. Font family: `monospace`.

| Style | Weight | Use |
|---|---|---|
| `headlineMedium` | w900 | Page titles |
| `titleLarge` | w900 | Section headers |
| `titleMedium` | w800 | Card titles |
| `bodyMedium` | w400 | Body text (white) |
| `bodyLarge` | w400 | Secondary body (text2) |
| `labelSmall` | w400 | Labels, captions (muted) |

---

## Folder Structure

```
lib/
├── main.dart                    Entry point, service init, home routing
├── core/
│   ├── constants/
│   │   └── gemma_config.dart    Model URLs, config constants
│   ├── errors/
│   │   └── app_exception.dart   Typed exceptions
│   ├── pocketclaw_theme.dart    Design tokens + ThemeData
│   └── status_words.dart        State label strings for UI
├── models/
│   ├── conversation.dart        Chat session entity (Hive)
│   ├── document.dart            RAG document metadata (Hive)
│   ├── message.dart             Chat message with multimodal support (Hive)
│   └── user_prefs.dart          User preferences
├── screens/                     Full-page UI — one file per screen
├── services/                    Singleton business logic — one file per domain
│   └── agent_loop/ background_task_engine/ dynamic_ui/
│       memory_engine/ primitive_engine/ skill_engine/ workflow_engine/
│       (empty dirs — reserved for future engines from further_plan.md)
└── widgets/                     Reusable UI components
```

---

## Service Layer Rules

- Services are singletons: `static final XxxService instance = XxxService._();`
- All services initialized once in `main.dart` — never inside a widget
- Never call `new XxxService()` anywhere
- Services catch their own exceptions — widgets react to state, not to exceptions
- `dispose()` is called only in `main.dart` teardown (or never for app-lifetime singletons)

---

## State Management Rules

- `ValueListenable<T>` + `ValueListenableBuilder` for reactive service state
- `setState` for local widget UI state only (loading flag, text input, etc.)
- Hive `Box<T>` for persistent data — use `box.listenable()` for reactive reads
- No Riverpod, No Provider, No BLoC — see D2 in DECISIONS.md

---

## Coding Rules

1. `build()` is pure — no service calls, no `Future.wait`, no side effects
2. `const` on every widget constructor that can be const
3. Colors, shadows, borders, and typography from `PocketClawTheme` tokens only
4. Every async-backed widget must show: **loading** → **error** → **data**
5. Dispose every `TextEditingController`, `ScrollController`,
   `AnimationController`, `StreamSubscription` in `dispose()`
6. After every `await`, check `if (!mounted) return;` before using `context`
7. Use `ListView.builder` — never `ListView(children: items.map(...).toList())`
8. `GemmaService.instance.generate()` is not re-entrant — check
   `state.value == GemmaState.ready` before calling

---

## Screen Checklist

Before marking any screen done, all 9 items must be checked:

```
[ ] Loading state shown (CircularProgressIndicator or skeleton)
[ ] Error state with user-visible message + retry action
[ ] Empty state for any list/data view (message + CTA)
[ ] Keyboard doesn't break layout (SingleChildScrollView or resizeToAvoidBottomInset)
[ ] All controllers disposed in dispose()
[ ] No fixed heights — responsive layout
[ ] if (!mounted) return after every await
[ ] const on all static widgets
[ ] Colors/shadows/borders from PocketClawTheme tokens only
```

---

## Out of Scope (do not implement without explicit request)

These are planned in `further_plan.md` but not yet built. The empty
`services/` subdirectories are reserved for them:

- **Primitive Engine** (`services/primitive_engine/`) — low-level tap/type/swipe actions
- **Skill Engine** (`services/skill_engine/`) — skill DSL and registry
- **Workflow Engine** (`services/workflow_engine/`) — IFTTT-style trigger-step automation
- **Memory Engine** (`services/memory_engine/`) — episodic/semantic/preference/skill memory
- **Agent Loop** (`services/agent_loop/`) — multi-step observe-plan-act cycles
- **Background Task Engine** (`services/background_task_engine/`) — persistent long-running jobs
- **Dynamic UI** (`services/dynamic_ui/`) — JSON-driven component rendering
- **Floating Overlay** — `FlutterOverlayWindow` integration (overlay isolate scaffolded, inactive)

---

## Quick Links — `.claude/` Config

### Rules
- `.claude/rules/gemma.md` — GemmaService usage, streaming, state machine
- `.claude/rules/rag.md` — RagService, indexing, retrieval, chunking
- `.claude/rules/hive.md` — Hive boxes, TypeAdapters, persistence
- `.claude/rules/services.md` — Singleton pattern, init/dispose
- `.claude/rules/widgets.md` — build() purity, 3 states, disposal
- `.claude/rules/theme.md` — Neobrutalism tokens, never inline
- `.claude/rules/performance.md` — RAM, isolate, StreamSubscription
- `.claude/rules/voice.md` — VoiceService, press-hold UX, STT

### Skills
- `.claude/skills/gemma-patterns/SKILL.md`
- `.claude/skills/rag-patterns/SKILL.md`
- `.claude/skills/device-actions-patterns/SKILL.md`
- `.claude/skills/screen-checklist/SKILL.md`
- `.claude/skills/smart-commit/SKILL.md`
- `.claude/skills/code-search-tools/SKILL.md`

### Commands
- `/new-screen` — scaffold a screen with 3 states
- `/new-service` — scaffold a singleton service
- `/pr-review` — invoke flutter-reviewer agent

---

## Universal Don'ts (flagged by `/pr-review`)

```
✗ Side effects or service calls in build()
✗ Color(0xFF...) inline — use PocketClawTheme.*
✗ TextStyle(...) outside theme — use Theme.of(context).textTheme.*
✗ Missing const on static widgets
✗ ListView(children: items.map(...).toList()) — use ListView.builder
✗ Missing if (!mounted) return after await
✗ Missing dispose() for any controller or StreamSubscription
✗ new XxxService() in a widget — services are singletons
✗ Calling GemmaService.instance.generate() without checking GemmaState.ready
✗ Missing loading / error / empty states
✗ Logic that belongs in a service written inside a widget
✗ Any code touching out-of-scope engines (Primitive, Workflow, Memory, Agent Loop)
```
```

- [ ] **Step 2: Verify flutter analyze still passes**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add CLAUDE.md — project instruction hub for agents"
```

---

## Task 4: Rules — gemma.md, rag.md, hive.md, services.md

**Files:**
- Create: `.claude/rules/gemma.md`
- Create: `.claude/rules/rag.md`
- Create: `.claude/rules/hive.md`
- Create: `.claude/rules/services.md`

**Interfaces:**
- Consumes: service APIs from ARCHITECTURE.md
- Produces: per-domain coding rules consumed by CLAUDE.md and `/pr-review`

- [ ] **Step 1: Create `.claude/rules/` directory and write `gemma.md`**

```bash
mkdir -p .claude/rules
```

Content of `.claude/rules/gemma.md`:
```markdown
# Rule: GemmaService Usage

## State Machine

```
notInstalled → installing → installed → loading → ready ⇄ generating
                                                     ↓
                                                   error
```

`EmbedderState` is independent: `notInstalled → installing → installed | error`

## Access Pattern

Always use the singleton:
```dart
GemmaService.instance   // correct
new GemmaService()      // NEVER — private constructor
```

## Before Generating

Always check state before calling `generate()`:
```dart
if (GemmaService.instance.state.value != GemmaState.ready) return;
final reply = await GemmaService.instance.generate(
  prompt,
  imageBytes: imageBytes,   // null for text-only
  onToken: (chunk) => setState(() => _partial += chunk),
);
```

`generate()` is NOT re-entrant. A second call while `generating` will throw
or silently fail. Disable the send button and voice trigger while
`state.value == GemmaState.generating`.

## Watching State in Widgets

```dart
ValueListenableBuilder<GemmaState>(
  valueListenable: GemmaService.instance.state,
  builder: (context, state, _) {
    if (state == GemmaState.error) {
      return ErrorWidget(GemmaService.instance.lastError?.toString() ?? 'Unknown error');
    }
    if (state != GemmaState.ready) {
      return LoadingWidget();
    }
    return ChatWidget();
  },
)
```

## Download Progress

```dart
ValueListenableBuilder<int>(
  valueListenable: GemmaService.instance.downloadProgress,
  builder: (context, progress, _) => LinearProgressIndicator(value: progress / 100),
)
```

## Error Handling

Services catch their own errors. Widgets react to `GemmaState.error`:
```dart
// CORRECT — react to state
if (state == GemmaState.error) showErrorBanner(GemmaService.instance.lastError);

// WRONG — widget catching service internals
try { await GemmaService.instance.generate(...); } catch (e) { ... }
```

## StreamSubscription

If you hold a `StreamSubscription` from an inference stream, cancel it in `dispose()`:
```dart
StreamSubscription<String>? _sub;

@override
void dispose() {
  _sub?.cancel();
  super.dispose();
}
```

## Embedder

The embedder is needed for RAG only. `RagService` calls `GemmaService.instance.getEmbedder()` internally — you don't need to call it directly from a screen.

## What NOT to Do

- Never call `GemmaService.instance.dispose()` from a widget or service
- Never call `GemmaService.instance.load()` or `install()` directly — use `ensureInstalled()` / `ensureLoaded()`
- Never instantiate `FlutterGemma` directly — always go through `GemmaService`
```

- [ ] **Step 2: Write `.claude/rules/rag.md`**

```markdown
# Rule: RagService Usage

## State Machine

```
notReady → ready ⇄ indexing
              ↓
           retrieving
              ↓
           error
```

## Indexing a Document

```dart
// 1. Extract text from file (PDF or TXT) — in service, not widget
// 2. Call indexDocument
final doc = await RagService.instance.indexDocument(
  text: extractedText,
  name: fileName,
  conversationId: currentConversationId,
  onProgress: (done, total) => setState(() => _progress = done / total),
);
// Returns Document object — save to DocumentStore
await DocumentStore.instance.save(doc);
```

Never call `indexDocument` from `build()` or directly in a widget tap handler
without a loading state guard. Set `RagState.indexing` is surfaced via
`RagService.instance.state`.

## Retrieval

```dart
final chunks = await RagService.instance.retrieve(
  query: userMessage,
  conversationId: conversationId,
  // topK defaults to 3 — do not override without profiling
);

// Inject into prompt as system context — never concatenate into user message
final context = chunks.map((c) => c.content).join('\n\n---\n\n');
final prompt = 'Context:\n$context\n\nUser: $userMessage';
```

Constants (do not change without testing):
- `topK = 3` (default in `RagService._defaultTopK`)
- `threshold = 0.4` (default in `RagService._defaultThreshold`)
- Chunk size: ~1200 chars (~300 tokens), minimum 80 chars

## Chunking

`RagService.instance.chunk(text)` returns `List<String>`. You don't need to call
this directly — `indexDocument` calls it internally. Only use it for testing.

## Document Starts (Fallback Retrieval)

For generic queries that don't match any chunk:
```dart
final starts = await RagService.instance.getDocStarts(
  conversationId: conversationId,
  perDocLimit: 3,  // first 3 chunks per document
);
```

## Deleting a Document

```dart
await RagService.instance.deleteDocument(doc);
await DocumentStore.instance.delete(doc.id);
```

## Watching RAG State in Widgets

```dart
ValueListenableBuilder<RagState>(
  valueListenable: RagService.instance.state,
  builder: (context, state, _) {
    if (state == RagState.indexing) return IndexingProgressWidget();
    if (state == RagState.error) return ErrorWidget(RagService.instance.lastError.toString());
    return DocumentListWidget();
  },
)
```

## What NOT to Do

- Never embed on the main thread outside of RagService — embedder calls are async and slow
- Never call `RagService.instance.init()` from a widget — it's called in `main.dart`
- Never concatenate retrieved chunks directly into the user message — inject as system context
- Never call `retrieve()` for every keypress — debounce or call on final message send only
```

- [ ] **Step 3: Write `.claude/rules/hive.md`**

```markdown
# Rule: Hive Persistence

## Box Opening — Order Matters

TypeAdapters MUST be registered before any box is opened. In `init()`:

```dart
// CORRECT
Hive.registerAdapter(ConversationAdapter());
Hive.registerAdapter(MessageAdapter());
await Hive.openBox<Conversation>('conversations');

// WRONG — crashes with HiveError: Cannot write, unknown type
await Hive.openBox<Conversation>('conversations');
Hive.registerAdapter(ConversationAdapter());
```

## Boxes in PocketClaw

| Box | Type | Service |
|---|---|---|
| `'conversations'` | `Box<Conversation>` | `ConversationStore` |
| `'documents'` | `Box<Document>` | `DocumentStore` |
| Prefs | `SharedPreferences` (not Hive) | `PrefsService` |

Open boxes only inside `XxxStore.init()` — never open boxes directly in widgets or other services.

## Reactive Reads

```dart
// Hive reactive pattern — re-builds when box changes
ValueListenableBuilder<Box<Conversation>>(
  valueListenable: ConversationStore.instance.box.listenable(),
  builder: (context, box, _) {
    final convs = box.values.toList();
    if (convs.isEmpty) return EmptyStateWidget();
    return ConversationListView(convs);
  },
)
```

## Writing Data

```dart
// Always use typed methods on the Store, not raw box.put()
await ConversationStore.instance.save(conversation);
await ConversationStore.instance.delete(conversation.id);
```

## Never Store Raw Maps

```dart
// WRONG
await box.put(key, {'title': 'Chat', 'messages': [...]});

// CORRECT
await box.put(key, Conversation(title: 'Chat', messages: []));
```

All stored types must have a registered `TypeAdapter<T>`.

## Closing Boxes

Boxes are closed in `main.dart` teardown (or app close). Never call
`Hive.close()` from a service or widget.

## TypeAdapter IDs

Each adapter needs a unique `typeId`. Check existing adapters before adding one
to avoid ID collisions:
- `Conversation` — check `ConversationAdapter.typeId`
- `Message` — check `MessageAdapter.typeId`
- `Document` — check `DocumentAdapter.typeId`
```

- [ ] **Step 4: Write `.claude/rules/services.md`**

```markdown
# Rule: Service Layer

## Singleton Pattern

Every service uses the same pattern:

```dart
class XxxService {
  XxxService._();
  static final XxxService instance = XxxService._();

  Future<void> init() async { ... }
  Future<void> dispose() async { ... }
}
```

## Init Sequence (main.dart)

Services init in this order (do not reorder without checking dependencies):

```dart
await ConversationStore.instance.init();  // Hive: conversations box
await DocumentStore.instance.init();      // Hive: documents box
await PrefsService.instance.init();       // SharedPreferences
await GemmaService.instance.init();       // Model detection
RagService.instance.init();              // sqlite-vec store (fire-and-forget)
// VoiceService — lazy init, called from onboarding or chat
```

## Rules

1. **Never instantiate a service in a widget:** `new XxxService()` is a bug.
   Always use `XxxService.instance`.

2. **Services own their error handling.** A service method either:
   - Returns a typed result: `Future<DeviceActionResult>`
   - Sets its own error state: `_state.value = GemmaState.error`
   - Throws only for programming errors (misuse of the API)
   
   Widgets react to state — they do not `try/catch` service calls.

3. **Services are app-lifetime singletons.** `dispose()` is called only in
   `main.dart` teardown (or not at all for services that don't need it).
   Never call `dispose()` from a widget or another service.

4. **No service imports another service's constructor.** Cross-service
   communication goes through method calls on `instance` — never by
   passing a service as a constructor parameter.

5. **Services expose state via `ValueListenable<T>`.** Widgets observe state
   with `ValueListenableBuilder` — they do not poll or use `Timer`.

## Adding a New Service

```dart
// lib/services/my_new_service.dart
class MyNewService {
  MyNewService._();
  static final MyNewService instance = MyNewService._();

  // State (if needed)
  final ValueNotifier<MyState> _state = ValueNotifier(MyState.idle);
  ValueListenable<MyState> get state => _state;

  Future<void> init() async {
    // initialize resources
  }

  // Public API methods here

  Future<void> dispose() async {
    // clean up resources
    _state.dispose();
  }
}
```

Then add to `main.dart` init sequence in the correct order.
```

- [ ] **Step 5: Verify flutter analyze still passes**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add .claude/rules/gemma.md .claude/rules/rag.md .claude/rules/hive.md .claude/rules/services.md
git commit -m "docs: add .claude/rules for gemma, rag, hive, services"
```

---

## Task 5: Rules — widgets.md, theme.md, performance.md, voice.md

**Files:**
- Create: `.claude/rules/widgets.md`
- Create: `.claude/rules/theme.md`
- Create: `.claude/rules/performance.md`
- Create: `.claude/rules/voice.md`

**Interfaces:**
- Produces: remaining 4 rules files completing the full rules set

- [ ] **Step 1: Write `.claude/rules/widgets.md`**

```markdown
# Rule: Widgets

## build() is Pure

`build()` must have no side effects. These are bugs:

```dart
// WRONG — side effect in build
Widget build(BuildContext context) {
  GemmaService.instance.generate(prompt);  // side effect
  return Text('...');
}

// WRONG — async in build
Widget build(BuildContext context) {
  Future.delayed(...);  // side effect
  return Text('...');
}
```

All async work belongs in event handlers (`onTap`, `onPressed`, `initState`,
`didChangeDependencies`) or `initState`/`didUpdateWidget`.

## 3 States — Always

Every widget backed by async data must handle all three states:

```dart
ValueListenableBuilder<GemmaState>(
  valueListenable: GemmaService.instance.state,
  builder: (context, state, _) {
    // 1. Loading
    if (state == GemmaState.loading || state == GemmaState.installing) {
      return const CircularProgressIndicator();
    }
    // 2. Error
    if (state == GemmaState.error) {
      return Column(children: [
        Text('Something went wrong', style: Theme.of(context).textTheme.bodyMedium),
        TextButton(onPressed: retry, child: const Text('Retry')),
      ]);
    }
    // 3. Data
    return ChatView();
  },
)
```

## Disposal

Always dispose in `dispose()`:

```dart
final TextEditingController _inputController = TextEditingController();
final ScrollController _scrollController = ScrollController();
StreamSubscription<String>? _streamSub;

@override
void dispose() {
  _inputController.dispose();
  _scrollController.dispose();
  _streamSub?.cancel();
  super.dispose();
}
```

## Mounted Check

After every `await`, check `mounted` before using `context` or calling `setState`:

```dart
await someAsyncOperation();
if (!mounted) return;
setState(() { ... });
```

## const Everywhere

```dart
// CORRECT
const SizedBox(height: 16)
const Icon(Icons.mic)
const Text('PocketClaw')

// WRONG — missing const when possible
SizedBox(height: 16)
```

Run `dart fix --apply` to add missing `const` automatically.

## ListView

```dart
// CORRECT
ListView.builder(
  itemCount: messages.length,
  itemBuilder: (context, i) => MessageBubble(message: messages[i]),
)

// WRONG — builds all items upfront
ListView(children: messages.map((m) => MessageBubble(message: m)).toList())
```

## Empty State

Any list/data view needs an empty state:

```dart
if (conversations.isEmpty) {
  return Center(
    child: Column(children: [
      Icon(Icons.chat_bubble_outline, color: PocketClawTheme.muted, size: 48),
      const SizedBox(height: 12),
      Text('No conversations yet', style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 8),
      FilledButton(onPressed: onNewChat, child: const Text('Start a chat')),
    ]),
  );
}
```

## Widget Type Hierarchy

- Use `StatelessWidget` when there is no mutable state
- Use `StatefulWidget` when managing local UI state (input, scroll position, etc.)
- Use `ValueListenableBuilder` (not `setState`) for service state observation
```

- [ ] **Step 2: Write `.claude/rules/theme.md`**

```markdown
# Rule: Theme & Design Tokens

## Never Inline Colors

```dart
// WRONG
Container(color: const Color(0xFF00E5FF))
Text('Hello', style: TextStyle(color: Colors.white))
BoxDecoration(color: const Color(0xFF171923))

// CORRECT
Container(color: PocketClawTheme.cyan)
Text('Hello', style: Theme.of(context).textTheme.bodyMedium)
BoxDecoration(color: PocketClawTheme.bg2)
```

## Color Tokens

```dart
import 'package:pocketclaw/core/pocketclaw_theme.dart';

PocketClawTheme.bg        // #0F1117 — scaffold background
PocketClawTheme.bg2       // #171923 — card / panel
PocketClawTheme.bg3       // #212431 — input / elevated surface
PocketClawTheme.cyan      // #00E5FF — primary accent
PocketClawTheme.purple    // #7C4DFF — secondary accent
PocketClawTheme.mint      // #00FFA3 — success / tertiary
PocketClawTheme.text      // #FFFFFF — primary text
PocketClawTheme.text2     // #B7BCCB — secondary text
PocketClawTheme.muted     // #7D8597 — placeholder / label
PocketClawTheme.warning   // #FFD166 — warnings
PocketClawTheme.error     // #FF5D73 — errors
PocketClawTheme.ink       // #05060A — shadow / button foreground
```

## Shadows & Borders

```dart
// Hard neobrutalism shadow (5,5 offset, 0 blur)
BoxDecoration(boxShadow: const [PocketClawTheme.hardShadow])

// 2px cyan border
BoxDecoration(border: PocketClawTheme.hardBorder())

// 2px purple border
BoxDecoration(border: PocketClawTheme.hardBorder(PocketClawTheme.purple))

// Full panel decoration (bg2 + cyan border + shadow + radius 8)
BoxDecoration decoration = PocketClawTheme.panel()

// Customized panel
BoxDecoration decoration = PocketClawTheme.panel(
  color: PocketClawTheme.bg3,
  border: PocketClawTheme.purple,
  radius: 12,
  shadow: false,
)
```

## Typography

Never create raw `TextStyle` with colors. Always use theme:

```dart
// CORRECT
Text('Title', style: Theme.of(context).textTheme.titleLarge)
Text('Body', style: Theme.of(context).textTheme.bodyMedium)

// WRONG
Text('Title', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white))
```

For color overrides on theme styles:
```dart
Text('Warning', style: Theme.of(context).textTheme.bodyMedium?.copyWith(
  color: PocketClawTheme.warning,
))
```

## Buttons

Use `FilledButton` (cyan bg, ink text) — defined in `PocketClawTheme.dark()`:
```dart
FilledButton(
  onPressed: onTap,
  child: const Text('DO IT'),
)
```

For ghost/outlined style:
```dart
OutlinedButton(
  style: OutlinedButton.styleFrom(
    side: const BorderSide(color: PocketClawTheme.cyan, width: 2),
    foregroundColor: PocketClawTheme.cyan,
  ),
  onPressed: onTap,
  child: const Text('CANCEL'),
)
```

## Standard Panel Widget Pattern

```dart
Container(
  decoration: PocketClawTheme.panel(),
  padding: const EdgeInsets.all(16),
  child: Column(children: [...]),
)
```
```

- [ ] **Step 3: Write `.claude/rules/performance.md`**

```markdown
# Rule: Performance

## RAM Budget

Gemma 4 E2B INT4 occupies ~1.5 GB. App overhead adds ~200–400 MB.
**Peak RAM: ~2 GB.** Mid-range Android devices may OOM. Keep widget trees lean.

Rules:
- No `Image.network` — all images are local assets
- No `Image.asset` inside `ListView.builder` without `cacheWidth`/`cacheHeight`
- No `Column` inside `SingleChildScrollView` with an inner `ListView` — use `CustomScrollView` with slivers

## Main Thread

GemmaService runs `flutter_gemma` inference on a native thread, but the
`generate()` call still occupies a Dart Future slot. While generating:

- The UI stays responsive (inference is off the main thread natively)
- `GemmaState.generating` is set — respect it, disable inputs
- The `onToken` callback fires on the main thread — keep it fast

```dart
// CORRECT — onToken just updates local state
await GemmaService.instance.generate(
  prompt,
  onToken: (chunk) {
    if (!mounted) return;
    setState(() => _buffer += chunk);  // fast, no heavy work
  },
);

// WRONG — heavy work in onToken
await GemmaService.instance.generate(
  prompt,
  onToken: (chunk) {
    parseMarkdown(chunk);     // slow
    saveToDatabase(chunk);    // I/O in hot path
  },
);
```

## StreamSubscription Lifecycle

Always cancel subscriptions in `dispose()`:

```dart
StreamSubscription<String>? _genSub;

void _startGeneration() {
  _genSub?.cancel();
  // assign new subscription
}

@override
void dispose() {
  _genSub?.cancel();
  super.dispose();
}
```

Failing to cancel leaves inference running in the background after the screen is gone.

## const Everywhere

`const` prevents widget rebuilds:

```dart
// CORRECT — rebuilt only when parent explicitly passes new data
const SizedBox(height: 16)
const Padding(padding: EdgeInsets.all(8))
const Icon(Icons.mic)

// WRONG — creates new object on every build()
SizedBox(height: 16)
```

Run `flutter analyze` — it flags missing `const`.

## ListView

```dart
// CORRECT — builds only visible items
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, i) => ItemWidget(item: items[i]),
)

// WRONG — builds ALL items immediately
ListView(children: items.map((i) => ItemWidget(item: i)).toList())
```

## Context Compaction

For long conversations, inject a compact summary instead of the full history.
`chat_screen.dart` already has compaction logic. Don't bypass it by passing
the full message list to `generate()`.
```

- [ ] **Step 4: Write `.claude/rules/voice.md`**

```markdown
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
```

- [ ] **Step 5: Verify flutter analyze still passes**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add .claude/rules/widgets.md .claude/rules/theme.md .claude/rules/performance.md .claude/rules/voice.md
git commit -m "docs: add .claude/rules for widgets, theme, performance, voice"
```

---

## Task 6: Skills

**Files:**
- Create: `.claude/skills/gemma-patterns/SKILL.md`
- Create: `.claude/skills/rag-patterns/SKILL.md`
- Create: `.claude/skills/device-actions-patterns/SKILL.md`
- Create: `.claude/skills/screen-checklist/SKILL.md`
- Create: `.claude/skills/smart-commit/SKILL.md`
- Create: `.claude/skills/code-search-tools/SKILL.md`

**Interfaces:**
- Consumes: rules from Tasks 4–5
- Produces: 6 skills invocable from Claude Code

- [ ] **Step 1: Create skills directories**

```bash
mkdir -p .claude/skills/gemma-patterns
mkdir -p .claude/skills/rag-patterns
mkdir -p .claude/skills/device-actions-patterns
mkdir -p .claude/skills/screen-checklist
mkdir -p .claude/skills/smart-commit
mkdir -p .claude/skills/code-search-tools
```

- [ ] **Step 2: Write `.claude/skills/gemma-patterns/SKILL.md`**

```markdown
# Skill: Gemma Patterns

Use this skill whenever working with inference, streaming, model lifecycle, or
context management in PocketClaw.

## 1. Basic Inference (text-only)

```dart
if (GemmaService.instance.state.value != GemmaState.ready) {
  // show "Model not ready" message
  return;
}

String response = '';
try {
  response = await GemmaService.instance.generate(
    prompt,
    onToken: (chunk) {
      if (!mounted) return;
      setState(() => _streamBuffer += chunk);
    },
  );
} catch (e) {
  if (!mounted) return;
  setState(() => _error = e.toString());
}
```

## 2. Multimodal Inference (image + text)

```dart
final bytes = await imageFile.readAsBytes();
final response = await GemmaService.instance.generate(
  prompt,
  imageBytes: bytes,
  onToken: (chunk) {
    if (!mounted) return;
    setState(() => _streamBuffer += chunk);
  },
);
```

## 3. Context Window Management

Gemma 4 E2B has a ~4096-token context window. For long conversations, compact
old messages before sending. `chat_screen.dart` contains `_buildCompactedPrompt()`
— use it rather than building prompts manually:

```dart
// Inside chat_screen.dart — already implemented
final prompt = _buildCompactedPrompt(messages, newUserMessage);
```

Do NOT pass the full `messages` list to `generate()` for conversations longer
than ~15 messages. Compaction is already wired — don't bypass it.

## 4. Loading State Pattern

Show the model lifecycle state in the UI:

```dart
ValueListenableBuilder<GemmaState>(
  valueListenable: GemmaService.instance.state,
  builder: (context, state, _) => switch (state) {
    GemmaState.notInstalled => InstallPromptWidget(),
    GemmaState.installing => ValueListenableBuilder<int>(
        valueListenable: GemmaService.instance.downloadProgress,
        builder: (_, progress, __) => DownloadProgressWidget(progress: progress),
      ),
    GemmaState.installed || GemmaState.loading => const ModelLoadingWidget(),
    GemmaState.ready || GemmaState.generating => ChatWidget(),
    GemmaState.error => ErrorWidget(
        error: GemmaService.instance.lastError?.toString() ?? 'Unknown error',
        onRetry: () => GemmaService.instance.resumeIfInstalled(),
      ),
  },
)
```

## 5. Embedder State (for RAG)

```dart
ValueListenableBuilder<EmbedderState>(
  valueListenable: GemmaService.instance.embedderState,
  builder: (context, state, _) {
    if (state == EmbedderState.installing) {
      return ValueListenableBuilder<int>(
        valueListenable: GemmaService.instance.embedderDownloadProgress,
        builder: (_, p, __) => Text('Downloading embedder: $p%'),
      );
    }
    if (state == EmbedderState.installed) return const Icon(Icons.check, color: PocketClawTheme.mint);
    if (state == EmbedderState.error) return Text('Embedder error', style: TextStyle(color: PocketClawTheme.error));
    return const SizedBox.shrink();
  },
)
```

## 6. Disabling Inputs During Generation

```dart
ValueListenableBuilder<GemmaState>(
  valueListenable: GemmaService.instance.state,
  builder: (context, state, _) {
    final isGenerating = state == GemmaState.generating;
    return IconButton(
      onPressed: isGenerating ? null : _sendMessage,
      icon: isGenerating
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.send),
    );
  },
)
```
```

- [ ] **Step 3: Write `.claude/skills/rag-patterns/SKILL.md`**

```markdown
# Skill: RAG Patterns

Use this skill when implementing document indexing, retrieval-augmented
generation, or any feature that reads from the knowledge base.

## 1. Full Indexing Flow

```dart
// Step 1: Pick a file
final result = await FilePicker.platform.pickFiles(
  type: FileType.custom,
  allowedExtensions: ['pdf', 'txt'],
);
if (result == null) return;

// Step 2: Extract text (in a service, not widget)
final file = File(result.files.single.path!);
String text;
if (file.path.endsWith('.pdf')) {
  text = await _extractPdfText(file);  // using syncfusion_flutter_pdf
} else {
  text = await file.readAsString();
}

// Step 3: Index (shows RagState.indexing while running)
setState(() => _isIndexing = true);
try {
  final doc = await RagService.instance.indexDocument(
    text: text,
    name: result.files.single.name,
    conversationId: _currentConversationId,
    onProgress: (done, total) => setState(() => _indexProgress = done / total),
  );
  await DocumentStore.instance.save(doc);
} finally {
  if (mounted) setState(() => _isIndexing = false);
}
```

## 2. Retrieval + Prompt Injection

```dart
Future<String> _buildRagPrompt(String userMessage, String conversationId) async {
  // Try semantic retrieval first
  final chunks = await RagService.instance.retrieve(
    query: userMessage,
    conversationId: conversationId,
  );

  if (chunks.isEmpty) {
    // Fallback: use document starts for broad/generic queries
    final starts = await RagService.instance.getDocStarts(
      conversationId: conversationId,
    );
    if (starts.isEmpty) return userMessage;  // no docs — plain prompt
    final context = starts.map((c) => c.content).join('\n\n---\n\n');
    return 'Context from your documents:\n$context\n\nUser: $userMessage';
  }

  final context = chunks.map((c) => '${c.docName}:\n${c.content}').join('\n\n---\n\n');
  return 'Context from your documents:\n$context\n\nUser: $userMessage';
}
```

## 3. Delete Document

```dart
Future<void> _deleteDoc(Document doc) async {
  await RagService.instance.deleteDocument(doc);
  await DocumentStore.instance.delete(doc.id);
  if (mounted) setState(() => _docs.remove(doc));
}
```

## 4. Watching RAG State

```dart
ValueListenableBuilder<RagState>(
  valueListenable: RagService.instance.state,
  builder: (context, state, _) => switch (state) {
    RagState.notReady => const CircularProgressIndicator(),
    RagState.indexing => const Text('Indexing document...'),
    RagState.retrieving => const Text('Searching knowledge base...'),
    RagState.error => Text(
        'RAG error: ${RagService.instance.lastError}',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: PocketClawTheme.error),
      ),
    RagState.ready => DocumentListWidget(),
  },
)
```

## 5. When to Use RAG

Only inject RAG context when:
1. The user has indexed at least one document in the current conversation
2. The user's message is likely a question about document content
3. `RagService.instance.state.value == RagState.ready`

Don't auto-retrieve for every message — it's slow and burns context window.
Check `await DocumentStore.instance.listForConversation(conversationId)` to
know if any documents exist before calling `retrieve()`.
```

- [ ] **Step 4: Write `.claude/skills/device-actions-patterns/SKILL.md`**

```markdown
# Skill: Device Actions Patterns

Use this skill when adding new device actions, modifying intent parsing, or
working with the `ChatCommandService` / `DeviceActionsService` layer.

## Architecture

```
User message (text)
    ↓
ChatCommandService.tryHandleWithGemma(text)
    │   Uses GemmaService to parse intent → JSON function call
    │   Falls back to ChatCommandService.tryHandle(text)  (regex-based)
    ↓
DeviceActionsService.instance.<action>(args)
    │   Sends via MethodChannel('pocketclaw/device')
    ↓
Kotlin (android/app/src/main/kotlin/.../MainActivity.kt)
```

## Calling from Chat

```dart
// In the message send handler (already in chat_screen.dart)
final reply = await ChatCommandService.instance.tryHandleWithGemma(userMessage);
if (reply != null) {
  // Device command was handled — reply is the user-facing response string
  _addAssistantMessage(reply);
  return;
}
// Fall through to normal Gemma inference
```

## DeviceActionsService API

```dart
// Flashlight
final result = await DeviceActionsService.instance.setTorch(true);
if (!result.ok) showError(result.message);

// Alarm
await DeviceActionsService.instance.openAlarm(label: 'Wake up', hour: 7, minute: 30);

// SMS
await DeviceActionsService.instance.openSms(phone: '+1234567890', body: 'On my way');

// Calendar event
await DeviceActionsService.instance.openCalendar(
  title: 'Team standup',
  dateTime: DateTime(2026, 7, 1, 9, 0),
);

// Web search
await DeviceActionsService.instance.openWebSearch('flutter isolates tutorial');

// All return DeviceActionResult(ok: bool, message: String)
```

## Adding a New Device Action

**Step 1 — Dart side** (`lib/services/device_actions_service.dart`):
```dart
Future<DeviceActionResult> myNewAction(String param) =>
    _invoke('myNewAction', {'param': param});
```

**Step 2 — Kotlin side** (`android/app/src/main/.../MainActivity.kt`):
```kotlin
"myNewAction" -> {
    val param = call.argument<String>("param") ?: ""
    // perform action
    result.success(mapOf("ok" to true, "message" to "Done"))
}
```

**Step 3 — Register in `ChatCommandService.tryHandle()`**:
```dart
if (_containsAny(lower, ['my trigger phrase', 'alternate trigger'])) {
  final param = _stripCommand(trimmed, ['my trigger phrase', 'alternate trigger']);
  return await DeviceActionsService.instance.myNewAction(param)
      .then((r) => r.message);
}
```

**Step 4 — Add to Gemma prompt** in `ChatCommandService.tryHandleWithGemma()`:
Add to the numbered list of available functions in the system prompt:
```
6. "myNewAction" args: {"param": "string"} (e.g. "trigger phrase example")
```

## Handling DeviceActionResult

```dart
final result = await DeviceActionsService.instance.setTorch(enabled);
if (result.ok) {
  _addAssistantMessage('Done! ${result.message}');
} else {
  _addAssistantMessage('Sorry, I couldn\'t do that: ${result.message}');
}
```

Never throw on `!result.ok` — these are user-facing failures (permission denied,
feature unavailable) not programming errors.
```

- [ ] **Step 5: Write `.claude/skills/screen-checklist/SKILL.md`**

```markdown
# Skill: Screen Checklist

Use this skill before marking any screen implementation as done.

## The 9-Item Gate

Work through each item. Do not mark a screen complete until all 9 are checked.

```
[ ] 1. LOADING STATE
    Every async-backed section shows a loading indicator or skeleton while data
    is being fetched/processed. CircularProgressIndicator or shimmer skeleton
    — never a blank/empty area.

[ ] 2. ERROR STATE
    Every async operation has a user-visible error state with a message and a
    retry action. The error message uses PocketClawTheme.error color.
    Example:
      Text('Failed to load', style: TextStyle(color: PocketClawTheme.error))
      TextButton(onPressed: _retry, child: const Text('Try again'))

[ ] 3. EMPTY STATE
    Any list or data view shows an empty state when there's nothing to display.
    Minimum: an icon, a one-line message, and a CTA button.

[ ] 4. KEYBOARD SAFETY
    Text inputs don't get covered by the keyboard.
    Either:
      resizeToAvoidBottomInset: true (default on Scaffold)
    Or:
      SingleChildScrollView wrapping the form

[ ] 5. DISPOSAL
    Every controller is disposed in dispose():
      _textController.dispose()
      _scrollController.dispose()
      _animController.dispose()
      _streamSub?.cancel()
    Check: search for 'Controller' in the file — is each one disposed?

[ ] 6. RESPONSIVE LAYOUT
    No hardcoded pixel heights that would break on different screen sizes.
    Use:
      Expanded / Flexible instead of fixed height
      MediaQuery.of(context).size for proportional sizes
      EdgeInsets.symmetric for consistent spacing

[ ] 7. MOUNTED CHECK
    Every use of context or setState after an await is guarded:
      if (!mounted) return;
    Search for 'await' in the file — is each one followed by a mounted check?

[ ] 8. CONST
    Every widget that can be const is const.
    Run: flutter analyze
    Check: any 'Prefer const' warnings?

[ ] 9. THEME TOKENS
    No Color(0xFF...) inline.
    No TextStyle(color: ...) outside of .copyWith() on a theme style.
    No hardcoded font sizes — use textTheme styles.
    Colors are always from PocketClawTheme.*
```

## Verification Commands

Run these before committing a new screen:

```bash
flutter analyze                    # catches missing const, type errors
flutter test test/screens/         # run screen tests if they exist
```
```

- [ ] **Step 6: Write `.claude/skills/smart-commit/SKILL.md`**

```markdown
# Skill: Smart Commit

Use this skill before making any git commit.

## Steps

### 1. Format

```bash
dart format lib/ test/
```

Expected: files reformatted or "Formatted 0 files"

### 2. Analyze

```bash
flutter analyze
```

Expected: `No issues found!`

If issues are found: fix them before committing. Do not commit with analyzer warnings.

### 3. Test

```bash
flutter test
```

Expected: all tests pass. If tests fail: fix them. Tests are a commit gate — no exceptions.

### 4. Review the diff

```bash
git diff --staged
```

Check for:
- Accidental debug code (`print(`, `debugPrint(` left in)
- Commented-out blocks meant to be removed
- Files that shouldn't be committed (`.dart_tool/`, `build/`, secrets)

### 5. Stage specific files

```bash
git add lib/screens/my_screen.dart test/screens/my_screen_test.dart
# DO NOT use: git add -A (can accidentally stage build artifacts or .env files)
```

### 6. Commit with conventional message

Format: `<type>: <short description>`

Types:
- `feat:` — new feature or screen
- `fix:` — bug fix
- `refactor:` — restructure without behavior change
- `test:` — add or update tests
- `docs:` — documentation only
- `chore:` — build config, dependencies, tooling

Examples:
```bash
git commit -m "feat: add document deletion with swipe gesture"
git commit -m "fix: cancel StreamSubscription in ChatScreen dispose"
git commit -m "refactor: extract PDF text extraction to dedicated method"
git commit -m "test: add RAGService retrieve error path tests"
```

Short (≤72 chars), imperative mood, no period at end.
```

- [ ] **Step 7: Write `.claude/skills/code-search-tools/SKILL.md`**

```markdown
# Skill: Code Search Tools

Use this skill when exploring or navigating the pocketclaw codebase.

## Tool Priority

1. **semble first** — semantic search, finds by intent not exact string
2. **grep second** — for exact strings, method names, type names
3. **Read third** — only after you know the exact file and need full context

## semble

```bash
# Find where GemmaService.generate is called
semble search "inference generate call" . 

# Find RAG retrieval logic
semble search "retrieve chunks RAG context" .

# Find error handling for model loading
semble search "model loading error state" .

# Find Hive box initialization
semble search "Hive openBox init" .

# Search docs only
semble search "context compaction" . --content docs

# Search config
semble search "embedder URL gecko" . --content config
```

Or via MCP in Claude Code:
```
mcp__semble__search("inference generate call", repo=".")
mcp__semble__find_related(file_path="lib/services/gemma_service.dart", line=416, repo=".")
```

## grep — Exact Symbol Search

```bash
# Find all callers of a method
grep -rn "\.generate(" lib/

# Find all ValueListenableBuilder usages
grep -rn "ValueListenableBuilder" lib/

# Find all GemmaState usages
grep -rn "GemmaState\." lib/

# Find all dispose() implementations
grep -rn "void dispose" lib/

# Find inline colors (violations)
grep -rn "Color(0xFF" lib/
```

## Key File Locations

| What | Where |
|---|---|
| Theme tokens | `lib/core/pocketclaw_theme.dart` |
| Model config | `lib/core/constants/gemma_config.dart` |
| App init + service init order | `lib/main.dart:470-490` |
| Gemma inference | `lib/services/gemma_service.dart:416` |
| RAG indexing | `lib/services/rag_service.dart:170` |
| RAG retrieval | `lib/services/rag_service.dart:250` |
| Device actions | `lib/services/device_actions_service.dart` |
| Intent parsing | `lib/services/chat_command_service.dart` |
| Main chat UI | `lib/screens/chat_screen.dart` |
| Voice capture | `lib/services/voice_service.dart:255` |

## flutter analyze

After any edit:
```bash
flutter analyze
```

Expected: `No issues found!`

If there are warnings: fix before moving on. Common fixes:
- `dart fix --apply` — auto-adds missing `const`, fixes minor style issues
- `dart format lib/` — fixes formatting
```

- [ ] **Step 8: Verify flutter analyze still passes**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add .claude/skills/
git commit -m "docs: add .claude/skills (gemma-patterns, rag-patterns, device-actions-patterns, screen-checklist, smart-commit, code-search-tools)"
```

---

## Task 7: Commands and Agent

**Files:**
- Create: `.claude/commands/new-screen.md`
- Create: `.claude/commands/new-service.md`
- Create: `.claude/commands/pr-review.md`
- Create: `.claude/agents/flutter-reviewer.md`

**Interfaces:**
- Consumes: rules from Tasks 4–5, screen-checklist skill from Task 6
- Produces: `/new-screen`, `/new-service`, `/pr-review` commands + `flutter-reviewer` agent

- [ ] **Step 1: Create directories**

```bash
mkdir -p .claude/commands
mkdir -p .claude/agents
```

- [ ] **Step 2: Write `.claude/commands/new-screen.md`**

```markdown
# Command: /new-screen

Scaffold a new Flutter screen for PocketClaw with all required boilerplate.

## Usage

```
/new-screen <ScreenName> [--stateless]
```

Examples:
- `/new-screen Settings` → `lib/screens/settings_screen.dart`
- `/new-screen DocumentViewer` → `lib/screens/document_viewer_screen.dart`
- `/new-screen About --stateless` → stateless variant

## What This Command Does

1. Creates `lib/screens/<snake_case>_screen.dart` with:
   - `StatefulWidget` (default) or `StatelessWidget` (with `--stateless`)
   - Loading / error / data states wired up
   - Proper `dispose()` override
   - Theme tokens imported
   - Screen checklist comments marking each of the 9 items

2. Creates `test/screens/<snake_case>_screen_test.dart` with:
   - Loading state test
   - Error state test
   - Data state test

## Generated Screen Template

```dart
import 'package:flutter/material.dart';
import '../core/pocketclaw_theme.dart';

class ${ScreenName}Screen extends StatefulWidget {
  const ${ScreenName}Screen({super.key});

  @override
  State<${ScreenName}Screen> createState() => _${ScreenName}ScreenState();
}

class _${ScreenName}ScreenState extends State<${ScreenName}Screen> {
  bool _isLoading = false;
  String? _error;

  // TODO: Add controllers here and dispose them below

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      // TODO: load data
      await Future.delayed(Duration.zero);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    // TODO: dispose controllers
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // [x] const on static widgets — mark when done
    // [x] theme tokens — mark when done
    // [x] keyboard safety — mark when done
    // [x] responsive layout — mark when done
    return Scaffold(
      backgroundColor: PocketClawTheme.bg,
      appBar: AppBar(title: const Text('${ScreenName}')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // [x] loading state
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    // [x] error state
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: PocketClawTheme.error)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    // [x] data state + empty state if applicable
    return const Center(child: Text('${ScreenName} — TODO'));
  }
}
```

After generating, complete the TODOs and run the screen checklist.
```

- [ ] **Step 3: Write `.claude/commands/new-service.md`**

```markdown
# Command: /new-service

Scaffold a new singleton service for PocketClaw.

## Usage

```
/new-service <ServiceName>
```

Examples:
- `/new-service Notification` → `lib/services/notification_service.dart`
- `/new-service Analytics` → `lib/services/analytics_service.dart`

## What This Command Does

1. Creates `lib/services/<snake_case>_service.dart` with:
   - Singleton pattern (`static final instance`)
   - `ValueNotifier<XxxState>` for state (with a minimal state enum)
   - `init()` and `dispose()` stubs
   - Error handling skeleton

2. Prints a reminder to add the service to the init sequence in `main.dart`

## Generated Service Template

```dart
import 'package:flutter/foundation.dart';

enum ${ServiceName}State { idle, loading, error }

class ${ServiceName}Service {
  ${ServiceName}Service._();
  static final ${ServiceName}Service instance = ${ServiceName}Service._();

  final ValueNotifier<${ServiceName}State> _state =
      ValueNotifier(${ServiceName}State.idle);
  ValueListenable<${ServiceName}State> get state => _state;

  Object? _lastError;
  Object? get lastError => _lastError;

  Future<void> init() async {
    // TODO: initialize resources
  }

  // TODO: add public API methods here

  Future<void> dispose() async {
    _state.dispose();
    // TODO: clean up resources
  }
}
```

## After Generating

1. Add to `main.dart` init sequence in the correct order:
   ```dart
   await ${ServiceName}Service.instance.init();
   ```

2. Run `flutter analyze` to confirm no issues.

3. Write tests in `test/services/${snake_case}_service_test.dart`.
```

- [ ] **Step 4: Write `.claude/commands/pr-review.md`**

```markdown
# Command: /pr-review

Invoke the flutter-reviewer agent to review the current uncommitted changes.

## Usage

```
/pr-review
```

## What This Command Does

1. Runs `git diff HEAD` to get the current diff
2. Passes it to the `flutter-reviewer` agent
3. Reports findings grouped by severity: CRITICAL / WARNING / SUGGESTION

## When to Use

Run `/pr-review` before every commit to catch violations before they land.
It is especially important for:
- New screens (checks all 9 checklist items)
- New services (checks singleton pattern, init/dispose)
- Any change touching GemmaService (checks state guards)

## Example Output

```
CRITICAL (must fix before commit):
  - chat_screen.dart:142 — missing if (!mounted) return after await
  - settings_screen.dart:89 — Color(0xFF00E5FF) inline, use PocketClawTheme.cyan

WARNING (should fix):
  - document_viewer_screen.dart:55 — missing const on SizedBox(height: 16)
  - rag_service.dart:210 — ListView with .toList() instead of ListView.builder

SUGGESTION (consider):
  - chat_screen.dart:320 — error state missing retry button
```
```

- [ ] **Step 5: Write `.claude/agents/flutter-reviewer.md`**

```markdown
# Agent: flutter-reviewer

You are a PocketClaw Flutter code reviewer. Review the provided diff and report
violations of the project's coding standards.

## How to Review

1. Run `git diff HEAD` to get the current diff if not provided
2. Check each changed Dart file against the rules below
3. Report findings grouped by severity

## Severity Levels

- **CRITICAL** — must fix before commit (correctness bug, crash risk, architecture violation)
- **WARNING** — should fix (style rule broken, missing state, performance issue)
- **SUGGESTION** — consider fixing (minor improvement, optional cleanup)

## CRITICAL Violations

### Missing mounted check
Any `await` not followed by `if (!mounted) return`:
```dart
// CRITICAL
await someService.doThing();
setState(() { ... });  // mounted not checked

// CORRECT
await someService.doThing();
if (!mounted) return;
setState(() { ... });
```

### Missing disposal
A `TextEditingController`, `ScrollController`, `AnimationController`, or
`StreamSubscription` declared but not disposed in `dispose()`.

### Service instantiated in widget
```dart
// CRITICAL
final service = GemmaService();  // private constructor bypassed
final service = new RagService();
```

### Inline Color
```dart
// CRITICAL
color: const Color(0xFF00E5FF)  // use PocketClawTheme.cyan
color: Colors.white              // use PocketClawTheme.text
```

### Raw TextStyle with color
```dart
// CRITICAL
style: const TextStyle(color: Colors.white, fontSize: 16)
// Use: Theme.of(context).textTheme.bodyMedium
```

### generate() without state check
```dart
// CRITICAL
await GemmaService.instance.generate(prompt);  // no GemmaState.ready check
```

### Out-of-scope engine code
Any code that adds logic to `services/primitive_engine/`,
`services/memory_engine/`, `services/workflow_engine/`,
`services/agent_loop/`, `services/background_task_engine/`,
`services/dynamic_ui/`, or implements the floating overlay without explicit
feature request.

## WARNING Violations

### Missing const
```dart
// WARNING
SizedBox(height: 16)   // should be const SizedBox(height: 16)
Icon(Icons.mic)        // should be const Icon(Icons.mic)
```

### ListView without builder
```dart
// WARNING
ListView(children: items.map((i) => Widget(i)).toList())
// Use: ListView.builder(itemCount: ..., itemBuilder: ...)
```

### Missing loading state
An async-backed widget section with no loading indicator or skeleton.

### Missing error state
An async operation with no error UI (message + retry).

### Missing empty state
A list view with no empty state UI.

### Side effect in build()
```dart
// WARNING
Widget build(BuildContext context) {
  _service.doThing();  // side effect — move to initState or event handler
  return ...;
}
```

## SUGGESTION Violations

### Missing empty state CTA
An empty state with only text, no action button.

### Hardcoded spacing
```dart
// SUGGESTION
SizedBox(height: 24)   // fine, but note in review for consistency
```

### Long build() method
`build()` over ~50 lines — consider extracting to named private methods.

## Report Format

```
## Review: <filename>

### CRITICAL
- Line <N>: <description>
  ```dart
  <offending code>
  ```
  Fix: <how to fix>

### WARNING
- Line <N>: <description>

### SUGGESTION
- Line <N>: <description>

---
```

If no violations found in a file: `<filename>: ✓ No violations found.`

End the review with a summary:
```
## Summary
- X critical (must fix)
- Y warnings (should fix)
- Z suggestions (consider)

flutter test status: [run `flutter test` and report pass/fail]
flutter analyze status: [run `flutter analyze` and report pass/fail]
```
```

- [ ] **Step 6: Verify flutter analyze still passes**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add .claude/commands/ .claude/agents/
git commit -m "docs: add .claude/commands (new-screen, new-service, pr-review) and flutter-reviewer agent"
```

---

## Self-Review

**Spec coverage check:**
- ✓ `settings.json` with dart format hook and permissions — Task 1
- ✓ `ARCHITECTURE.md` with layer diagram, service APIs, init sequence — Task 2
- ✓ `DECISIONS.md` with 9 decisions — Task 2
- ✓ `CHANGELOG.md` seeded with shipped features — Task 2
- ✓ `ERRORS.md` seeded from known failures — Task 2
- ✓ `CLAUDE.md` with all 12 sections — Task 3
- ✓ `gemma.md` — Task 4
- ✓ `rag.md` — Task 4
- ✓ `hive.md` — Task 4
- ✓ `services.md` — Task 4
- ✓ `widgets.md` — Task 5
- ✓ `theme.md` — Task 5
- ✓ `performance.md` — Task 5
- ✓ `voice.md` — Task 5
- ✓ `gemma-patterns/SKILL.md` — Task 6
- ✓ `rag-patterns/SKILL.md` — Task 6
- ✓ `device-actions-patterns/SKILL.md` — Task 6
- ✓ `screen-checklist/SKILL.md` — Task 6
- ✓ `smart-commit/SKILL.md` — Task 6
- ✓ `code-search-tools/SKILL.md` — Task 6
- ✓ `new-screen.md` — Task 7
- ✓ `new-service.md` — Task 7
- ✓ `pr-review.md` — Task 7
- ✓ `flutter-reviewer.md` — Task 7

All 22 files accounted for. No placeholders. All exact method/enum names verified against live source.
