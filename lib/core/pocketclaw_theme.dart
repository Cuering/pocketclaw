import 'package:flutter/material.dart';

class PocketClawTheme {
  PocketClawTheme._();

  static const Color bg = Color(0xFF0F1117);
  static const Color bg2 = Color(0xFF171923);
  static const Color bg3 = Color(0xFF212431);
  static const Color cyan = Color(0xFF00E5FF);
  static const Color purple = Color(0xFF7C4DFF);
  static const Color mint = Color(0xFF00FFA3);
  static const Color text = Color(0xFFFFFFFF);
  static const Color text2 = Color(0xFFB7BCCB);
  static const Color muted = Color(0xFF7D8597);
  static const Color warning = Color(0xFFFFD166);
  static const Color error = Color(0xFFFF5D73);
  static const Color ink = Color(0xFF05060A);

  static const BoxShadow hardShadow = BoxShadow(
    color: ink,
    offset: Offset(5, 5),
    blurRadius: 0,
  );

  static Border hardBorder([Color color = cyan, double width = 2]) =>
      Border.all(color: color, width: width);

  static BoxDecoration panel({
    Color color = bg2,
    Color border = cyan,
    double radius = 8,
    bool shadow = true,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: hardBorder(border),
      boxShadow: shadow ? const [hardShadow] : null,
    );
  }

  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
      primary: cyan,
      onPrimary: ink,
      secondary: purple,
      onSecondary: text,
      tertiary: mint,
      onTertiary: ink,
      error: error,
      onError: ink,
      surface: bg2,
      onSurface: text,
      surfaceContainer: bg2,
      surfaceContainerHighest: bg3,
      onSurfaceVariant: text2,
      outline: cyan,
      outlineVariant: Color(0x33FFFFFF),
      primaryContainer: bg3,
      onPrimaryContainer: text,
      errorContainer: Color(0xFF3A1720),
      onErrorContainer: text,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      fontFamily: 'monospace',
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          fontFamily: 'monospace',
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: text,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
        headlineSmall: TextStyle(
          color: text,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
        titleLarge: TextStyle(
          color: text,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
        titleMedium: TextStyle(
          color: text,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        titleSmall: TextStyle(
          color: text,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        bodyLarge: TextStyle(color: text2, letterSpacing: 0),
        bodyMedium: TextStyle(color: text, letterSpacing: 0),
        bodySmall: TextStyle(color: text2, letterSpacing: 0),
        labelSmall: TextStyle(color: muted, letterSpacing: 0),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cyan,
          foregroundColor: ink,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
            fontFamily: 'monospace',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: text, width: 2),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: text,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0x33FFFFFF), width: 1.5),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bg3,
        hintStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: text, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: text, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: cyan, width: 3),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bg3,
        contentTextStyle: const TextStyle(
          color: text,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: cyan, width: 2),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
