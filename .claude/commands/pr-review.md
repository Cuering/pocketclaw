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
