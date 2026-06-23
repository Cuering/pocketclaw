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
