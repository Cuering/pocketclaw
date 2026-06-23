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
