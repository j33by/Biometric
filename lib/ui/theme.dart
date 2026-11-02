import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFFF1F0EB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF7F6F2);
  static const border = Color(0xFFD9D7CF);
  static const ink = Color(0xFF1C2126);
  static const muted = Color(0xFF6A7078);
  static const faint = Color(0xFF9AA0A7);
  static const side = Color(0xFF18222C);
  static const sideHi = Color(0xFF223140);
  static const sideText = Color(0xFFB8C2CC);
  static const accent = Color(0xFF1F4E79);
  static const accentSoft = Color(0xFFDCE7F1);
  static const ok = Color(0xFF2E7D50);
  static const okSoft = Color(0xFFDDEFE3);
  static const warn = Color(0xFFA86A0B);
  static const warnSoft = Color(0xFFF6E8CC);
  static const bad = Color(0xFFAF3A2E);
  static const badSoft = Color(0xFFF4DAD6);
}

const String kFont = 'Segoe UI';

ThemeData buildTheme() {
  const scheme = ColorScheme.light(
    primary: C.accent,
    onPrimary: Colors.white,
    secondary: C.accent,
    surface: C.surface,
    onSurface: C.ink,
    error: C.bad,
    outline: C.border,
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(3),
    borderSide: const BorderSide(color: C.border),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: kFont,
    scaffoldBackgroundColor: C.bg,
    dividerColor: C.border,
    splashFactory: NoSplash.splashFactory,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 13, color: C.ink),
      bodySmall: TextStyle(fontSize: 12, color: C.muted),
      titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: C.accent, width: 1.4)),
      labelStyle: const TextStyle(fontSize: 12, color: C.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.ink,
        side: const BorderSide(color: C.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: C.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: const BorderSide(color: C.border)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, width: 420),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(3)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );
}
