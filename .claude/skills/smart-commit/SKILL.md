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
