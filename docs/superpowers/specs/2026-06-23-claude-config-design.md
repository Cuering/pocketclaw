# PocketClaw — Claude Config & Coding Rules Design

**Date:** 2026-06-23
**Scope:** `.claude/` configuration only — no changes to `lib/` Dart code
**Approach:** Option B — Domain-driven (adapted for pocketclaw's actual stack)
**Owner:** Manoj Shetty (personal side project)

---

## Goal

Bring the same agent-collaboration quality to pocketclaw that motoxapp has:
- A living CLAUDE.md that orients any agent before every task
- Rules that enforce pocketclaw's actual patterns (not generic Flutter)
- Skills that accelerate work on the AI/RAG/voice domain
- Commands and a reviewer agent for consistency

This is a Claude config-only change. No Dart code is modified.

---

## File Inventory

```
pocketclaw/
├── CLAUDE.md                              ← Project instruction hub
├── ARCHITECTURE.md                        ← System map + data flow
├── DECISIONS.md                           ← Settled choices with rationale
├── CHANGELOG.md                           ← Append-only commit history
└── ERRORS.md                              ← Failure logs + resolutions

.claude/
├── settings.json                          ← Hooks + permissions
├── rules/
│   ├── gemma.md
│   ├── rag.md
│   ├── hive.md
│   ├── services.md
│   ├── widgets.md
│   ├── theme.md
│   ├── performance.md
│   └── voice.md
├── skills/
│   ├── gemma-patterns/SKILL.md
│   ├── rag-patterns/SKILL.md
│   ├── device-actions-patterns/SKILL.md
│   ├── screen-checklist/SKILL.md
│   ├── smart-commit/SKILL.md
│   └── code-search-tools/SKILL.md
├── commands/
│   ├── new-screen.md
│   ├── new-service.md
│   └── pr-review.md
└── agents/
    └── flutter-reviewer.md
```

Total: 22 files

---

## CLAUDE.md Structure

1. **Before every task** — read ARCHITECTURE.md, DECISIONS.md, CHANGELOG.md, ERRORS.md
2. **App identity** — pocketclaw, Manoj Shetty personal project, Flutter Android, offline AI assistant, Gemma 4 E2B (INT4 1.5GB) + Gecko 110M embedder (INT8 110MB), Hive persistence, neobrutalism design
3. **Non-negotiables (6)**
   - Model privacy: no network calls from GemmaService/RAGService
   - Performance: Gemma lives in its own isolate; watch peak RAM (~2GB)
   - UX feel: neobrutalism — bold borders, flat shadows, primary yellow accent
   - AI reliability: always degrade gracefully when model busy/loading
   - Tests = commit gate (`flutter test` must pass before any commit)
   - Minimal scope: nothing from the out-of-scope list
4. **Design system** — neobrutalism tokens (from `ui_design.md`): colors, shadow levels (none/soft/hard), 2px black border, typography scale
5. **Folder structure** — annotated layer-first tree (screens/services/models/widgets/core — not changing)
6. **Service layer rules** — singleton init in `main.dart`, never instantiate inside a widget, dispose in `main.dart` teardown
7. **State management rules** — `ValueListenable`/Hive boxes for reactive state; `setState` for local UI only; no Riverpod/Provider/BLoC
8. **Coding rules** — build() pure, const everywhere, tokens only, all 3 states, dispose always, `mounted` check after every `await`
9. **Screen checklist** — 9-item gate (see below)
10. **Out of scope** — items in `further_plan.md` not yet built: Primitive Engine, Memory Engine, Workflow Engine, Agent Loop, Background Task Engine, Dynamic UI, floating overlay
11. **Quick links** — 14 rules/skills/commands in `.claude/`
12. **Universal Don'ts** — flagged by `/pr-review` (see below)

---

## settings.json

### Hook
```json
"PostToolUse": [{
  "matcher": "Write|Edit",
  "hooks": [{ "type": "command", "command": "dart format $CLAUDE_TOOL_INPUT_PATH 2>/dev/null; true" }]
}]
```
Runs `dart format` automatically on every file write/edit.

### Permissions — allow
```
flutter pub get/upgrade/analyze/test/run/build/devices/doctor/pub deps
dart format/fix/analyze
git diff/log/status/add/branch/checkout/fetch/pull
semble
```

### Permissions — deny
```
git push --force*
rm -rf lib/*
flutter clean && flutter pub get && flutter run --release*
```

---

## Rules — Content Summary

| File | Key invariants |
|---|---|
| `gemma.md` | Always stream via `streamChat`; never call `GemmaService` from a widget directly; check `isModelLoaded` before inference; handle `GemmaException` with user-facing fallback; never call `dispose()` on the service mid-session |
| `rag.md` | Index via `RAGService.indexDocument` only; topK=3, threshold=0.5 always; never embed on the main thread; chunk size ~300 tokens (~1200 chars); retrieval result injected as system context, never concatenated into user message |
| `hive.md` | Open boxes in `initHive()` only; register TypeAdapters before opening any box; never store `Map<dynamic,dynamic>` — typed adapters only; close boxes in `main.dart` teardown |
| `services.md` | Services are singletons, initialized once in `main.dart`; never call `new XxxService()` in a widget; dispose only in `main.dart` teardown; services own their error handling, widgets never catch service internals |
| `widgets.md` | `build()` is pure — no side effects, no service calls; every async-backed widget shows loading/error/data; dispose all `TextEditingController`, `ScrollController`, `AnimationController`; `if (!mounted) return` after every `await` |
| `theme.md` | Colors only from `PocketClawTheme` — never `Color(0xFF...)` inline; shadows from 3-level system (none/soft/hard); border always 2px solid black; typography from theme tokens only |
| `performance.md` | GemmaService runs in its isolate — never block main thread; cancel inference `StreamSubscription` in dispose; watch peak RAM (1.5GB model + overhead ≈ 2GB); `const` on all static widgets; `ListView.builder` not `ListView` with `.toList()` |
| `voice.md` | Initialize `VoiceService` lazily (not at startup); press-hold UX only — no toggle; always `stopListening()` in dispose; handle `SpeechToText` permission denial with a user-visible message; never start listening while model is streaming |

---

## Skills — Content Summary

| Skill | What it teaches |
|---|---|
| `gemma-patterns` | Correct `streamChat` usage, context window management, when/how to trigger compaction, isolate message passing, loading/error state patterns for inference |
| `rag-patterns` | Full indexing flow (pick file → extract text → chunk → embed → store), retrieval flow (embed query → vector search → inject context), how to add a new document type |
| `device-actions-patterns` | How `ChatCommandService` parses intents, how `DeviceActionsService` maps to MethodChannel calls, how to add a new device action (Dart side + Kotlin side) |
| `screen-checklist` | 9-item gate: (1) loading state, (2) error state with retry, (3) empty state, (4) keyboard safety, (5) all controllers disposed, (6) no fixed heights, (7) `mounted` check, (8) `const` on static widgets, (9) theme tokens only |
| `smart-commit` | dart format → flutter analyze → review diff → stage specific files → commit with conventional message format |
| `code-search-tools` | semble first (`mcp__semble__search`), then grep; `flutter analyze` after edits; `find_related` for discovering similar code |

---

## Commands — Behavior

| Command | Scaffolds |
|---|---|
| `/new-screen` | A `ConsumerStatefulWidget` (or `StatefulWidget`) with loading/error/data states, proper `dispose()`, `mounted` check, theme tokens, and a `TODO` marker for each section |
| `/new-service` | A singleton class with `static final _instance` pattern, `Future<void> init()`, `Future<void> dispose()`, and error handling skeleton |
| `/pr-review` | Invokes `flutter-reviewer` agent against current `git diff` |

---

## Agent — flutter-reviewer

The reviewer checks the diff against the Universal Don'ts list:

**Code violations:**
- Side effects or service calls in `build()`
- Inline `Color(0xFF...)` or raw `TextStyle(...)` outside theme
- Missing `const` on static widgets
- `ListView` with `.toList()` instead of `ListView.builder`
- Missing `if (!mounted) return` after an `await`
- Missing `dispose()` for any controller

**Architecture violations:**
- Widget directly instantiating or calling a service constructor
- GemmaService called from a widget (must go through a service method)
- Logic inside a widget that belongs in a service
- Accessing another screen's state directly

**State violations:**
- Missing loading state (must show skeleton or indicator)
- Missing error state (must show message + retry)
- Missing empty state for list/data views

**Scope violations:**
- Any implementation touching out-of-scope items (Primitive Engine, Workflow Engine, Memory Engine, Agent Loop, floating overlay)

---

## Relay Docs — What Each Contains

| File | Content |
|---|---|
| `ARCHITECTURE.md` | Layer diagram, data flow (widget → service → model → Hive/Gemma), feature inventory, key file map |
| `DECISIONS.md` | Settled choices: no Riverpod (Hive reactive), no go_router (simple Navigator), layer-first not feature-first, singleton services, neobrutalism design, Android-only v1 |
| `CHANGELOG.md` | Append-only: date + what shipped, seeded with current shipped state |
| `ERRORS.md` | Known failure patterns + resolutions (seeded from `debugging-playbook.md`) |

---

## Screen Checklist (9 items)

```
[ ] loading state shown (skeleton or progress indicator)
[ ] error state with retry action
[ ] empty state with message + CTA (for list/data views)
[ ] keyboard doesn't break layout (SingleChildScrollView or resizeToAvoidBottomInset)
[ ] all controllers disposed in dispose()
[ ] no fixed heights — responsive layout
[ ] if (!mounted) return before any post-await context use
[ ] const on all static widgets
[ ] colors/spacing/shadows from PocketClawTheme tokens only
```

---

## Universal Don'ts (flagged by /pr-review)

```
- Side effects in build()
- Color(0xFF...) or TextStyle(...) inline (not from theme)
- Missing const on static widgets
- ListView with children: items.toList() — use ListView.builder
- Missing if (!mounted) return after await
- Missing dispose() for TextEditingController / ScrollController / etc.
- Widget instantiating a service: new XxxService()
- Widget calling GemmaService.instance directly
- Missing loading / error / empty states
- Any code touching out-of-scope engines
```

---

## Out of Scope (this config change)

- No changes to `lib/` Dart code
- No lib/ folder restructuring
- No Riverpod/go_router introduction
- No implementation of Primitive Engine, Memory Engine, Workflow Engine, Agent Loop, floating overlay

---

## Spec Self-Review

- No placeholders or TBDs remaining
- Architecture section matches the layer-first structure confirmed in exploration
- Out-of-scope list matches `further_plan.md` items
- Rules cover all major services in `lib/services/`
- Skills map to the 3 core AI subsystems (Gemma, RAG, device actions) + 3 workflow skills
- No contradictions between sections
- Scope is focused: 22 files, all config, no Dart changes
