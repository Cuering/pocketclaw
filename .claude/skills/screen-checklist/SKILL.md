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
