# Phase 4 Design — Dynamic Components + Skill Marketplace

**Status:** Approved (brainstorming complete)
**Date:** 2026-06-26
**Depends on:** Phases 1–3 (Primitive Engine, Skill Engine, Workflow Engine + Background Tasks) — all merged to `dev`.

---

## Goal

Two subsystems shipped in one phase:

1. **Dynamic Components** — JSON-driven rich UI. Gemma (or a skill) emits a
   component spec; PocketClaw renders a card / list / key_value / buttons block
   instead of plain text.
2. **Skill Marketplace** — export/import skills and workflows as self-contained
   `.pcskill` bundle files. Offline-first; architecture-ready for a future
   "PocketClaw Community".

---

## Architecture

The key unification: a `render_component` primitive does **not** own a rendering
surface. It emits a ```` ```pcui {...}``` ```` block as its step output, which
flows through the **same** chat-rendering path as a model-emitted block. One
renderer, two sources.

```
DYNAMIC COMPONENTS
──────────────────
Source A — model:  Gemma reply text contains  ```pcui {...}```
Source B — skill:  render_component primitive → outputs ```pcui {...}``` as result
                              │
                              ▼
        ChatScreen detects ```pcui``` blocks in assistant text
                              │
                              ▼
        DynamicUiService.parse(json) → ComponentSpec?   (null on bad spec)
                              │
                              ▼
        DynamicComponentWidget → card / list / key_value / buttons
                              │  (parse fails → render raw text, never crash)
                         buttons tap → ChatCommandService with button.command

SKILL MARKETPLACE
─────────────────
Export:  pick skills/workflows → PcSkillCodec.encode → temp .pcskill → share_plus sheet
Import:  file_picker → PcSkillCodec.decode → validate → re-mint IDs + rewire refs
         → SkillStore / WorkflowStore
```

### New files

| File | Responsibility |
|---|---|
| `lib/services/dynamic_ui/component_spec.dart` | `ComponentSpec` model + strict `fromJson` (validates `type`) |
| `lib/services/dynamic_ui/dynamic_ui_service.dart` | Singleton: `parse(json) → ComponentSpec?`, `extractBlocks(text)` |
| `lib/widgets/dynamic_component_widget.dart` | Renders a `ComponentSpec` with theme tokens |
| `lib/services/marketplace/pcskill_codec.dart` | encode/decode bundle, ID re-mint, ref rewire |
| `lib/services/marketplace/marketplace_service.dart` | Singleton: `exportBundle(...)`, `importFromFile()` |

### Modified files

| File | Change |
|---|---|
| `lib/services/primitive_engine/primitive_models.dart` | Add `render_component` to the primitive switch + validation |
| `lib/services/primitive_engine/primitive_engine.dart` | Handle `render_component` execution (returns pcui block) |
| `lib/screens/chat_screen.dart` | Detect ```` ```pcui``` ```` blocks in assistant bubbles; "Import skill…" menu item |
| `lib/screens/skills_screen.dart` | Long-press skill → Export |
| `lib/screens/workflows_screen.dart` | Long-press → Export (bundles workflow + referenced skills) alongside Delete |
| `lib/main.dart` | Init `DynamicUiService`, `MarketplaceService` |
| `pubspec.yaml` | Add `share_plus` |

### Reused as-is

`SkillModel.toJson/fromJson` + `version`, `WorkflowModel.toJson/fromJson`,
`file_picker ^11.0.2`, `path_provider ^2.1.5`. One new dependency: `share_plus`.

---

## Data Models & Formats

### `ComponentSpec` (Core 4)

Every spec carries a `type`; the rest is type-specific. Unknown/invalid `type`
→ `parse()` returns `null` → chat falls back to raw text.

```jsonc
// card
{ "type": "card", "title": "Flashcards Ready", "body": "Created 12 cards from your PDF." }

// list  (items: title required, subtitle optional)
{ "type": "list", "items": [
    { "title": "Morning Routine", "subtitle": "3 skills" },
    { "title": "Invoice Sweep",   "subtitle": "2 skills" } ] }

// key_value  (rows: label → value)
{ "type": "key_value", "title": "Invoice #4471", "rows": [
    { "label": "Vendor", "value": "Acme" },
    { "label": "Due",    "value": "₹12,400" } ] }

// buttons  (each: label + command re-entered into chat)
{ "type": "buttons", "buttons": [
    { "label": "Run it",    "command": "run workflow invoice sweep" },
    { "label": "Show docs", "command": "list documents" } ] }
```

Dart shape:

```dart
class ComponentSpec {
  final String type;                 // 'card' | 'list' | 'key_value' | 'buttons'
  final String? title;
  final String? body;                // card
  final List<ListItem>? items;       // list
  final List<KvRow>? rows;           // key_value
  final List<UiButton>? buttons;     // buttons
}
class ListItem { final String title; final String? subtitle; }
class KvRow    { final String label; final String value; }
class UiButton { final String label; final String command; }
```

`fromJson` throws `FormatException` on a malformed spec (missing required field,
wrong type, unknown `type`). `DynamicUiService.parse` catches it → returns `null`.

### `extractBlocks(text)`

Scans assistant text for fenced ```` ```pcui … ``` ```` blocks (case-insensitive
fence tag). Returns the ordered list of inner JSON strings. Text outside blocks
is preserved by the caller for mixed text+component bubbles.

### `.pcskill` bundle

```jsonc
{
  "format": "pcskill/1",            // version gate — reject unknown
  "exportedAt": "2026-06-26T10:00:00.000Z",
  "skills":    [ { …SkillModel.toJson… } ],
  "workflows": [ { …WorkflowModel.toJson… } ]   // optional; may be []
}
```

### Import algorithm

1. Parse + validate `format == "pcskill/1"`; else user-visible error, nothing written.
2. Each skill → mint **new id** (`skill-<ts>-<rand>`), keep name/steps/version.
   Build `oldSkillId → newSkillId` map.
3. Each workflow → mint new id; **rewrite `stepSkillIds`** through the map. A step
   id absent from the bundle is dropped and recorded in `warnings` (workflow still
   imports).
4. Save skills first, then workflows (dependency order).
5. Return `ImportResult { int skillsAdded, int workflowsAdded, List<String> warnings }`.

ID re-minting means import **never** collides with or overwrites existing items —
an imported skill is always a fresh copy.

---

## Model Prompting (enabling Source A)

For Gemma to *emit* `pcui` blocks at all, the chat system prompt must document
the format — otherwise only the deterministic `render_component` primitive path
(Source B) produces rich UI.

Decision, balancing the small on-device model's prompt budget and over-emission
risk:

- The `render_component` primitive is the **reliable workhorse** — skills and
  workflows produce rich UI deterministically, no prompting needed.
- Add a **concise** pcui guide (the Core 4 shapes, ~10 lines) to the chat system
  prompt so the model *can* emit components when genuinely useful, with an
  explicit instruction to prefer plain text and only emit a block when the data
  is clearly tabular/structured.
- Because the renderer degrades unknown/malformed blocks to raw text, the worst
  case of the model never emitting (or emitting badly) is simply unused capability
  — never a crash or a broken bubble.

This makes "Both" real while keeping the primitive path as the dependable one.

---

## Error Handling

| Failure | Behavior |
|---|---|
| Malformed `pcui` block in model reply | `parse()` → `null` → render raw text bubble unchanged |
| `render_component` primitive bad args | Returns `ok: false` with message (consistent with other primitives); workflow continues per existing step-failure handling |
| Button command fails downstream | Handled by `ChatCommandService` like any typed command |
| Import: unknown `format` / unparseable JSON | Snackbar "Not a valid .pcskill file"; nothing written |
| Import: workflow refs a skill not in bundle | Skill dropped from that workflow, recorded in `warnings`, import succeeds |
| Export: share sheet cancelled | No-op |

---

## UI Entry Points

- **Export skill:** `SkillsScreen` long-press → "Export" → single-skill bundle → share sheet.
- **Export workflow:** `WorkflowsScreen` long-press → menu "Export" (bundles workflow
  + referenced skills) alongside existing "Delete".
- **Import:** new "Import skill…" item in chat `PopupMenu` → `file_picker` →
  `MarketplaceService.importFromFile()` → summary snackbar
  ("Added 2 skills, 1 workflow").
- **Dynamic components:** no new screen — render inline in `ChatScreen` bubbles.

---

## Testing

- `DynamicUiService.parse` — each Core 4 valid spec parses; malformed / unknown-type → `null`. Pure, no Flutter binding.
- `extractBlocks` — single block, multiple blocks, no block, malformed fence.
- `PcSkillCodec` — encode→decode round-trip; ID re-mint yields fresh ids;
  workflow ref rewiring; missing-skill-ref warning; bad `format` rejected.
- `render_component` primitive — valid args → ok with pcui output; bad args → ok:false.
- Widget tests for `DynamicComponentWidget` deferred unless cheap (screens aren't
  widget-tested today; consistent with project convention).

---

## Non-Goals (YAGNI)

- No `table` / `image` / `chart` components in v1 (Core 4 only).
- No remote/community fetch — `.pcskill` exchange is manual file sharing only.
- No skill *versioning conflict resolution* — re-minting sidesteps it entirely.
- No editing of imported skills beyond what the existing Skills UI already offers.

---

## Design System & Constraints (binding)

- 100% on-device; no network calls in any Phase 4 service.
- All UI from `PocketClawTheme` tokens; neobrutalism (hard borders, hard shadow).
- Services are singletons, init in `main.dart` only.
- `ValueListenable` + `ValueListenableBuilder` for state; no Riverpod/Provider/BLoC.
- `flutter test` green before any commit.
- Component rendering must degrade to raw text — never crash on a bad spec.
