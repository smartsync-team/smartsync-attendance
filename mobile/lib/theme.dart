import 'package:flutter/material.dart';

/// Colour tokens taken from the HTML prototype.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brand,
    required this.brandSoft,
    required this.ok,
    required this.okSoft,
    required this.warn,
    required this.warnSoft,
    required this.muted,
    required this.line,
    required this.panel,
  });

  final Color brand, brandSoft, ok, okSoft, warn, warnSoft, muted, line, panel;

  static const light = AppColors(
    brand: Color(0xFF1F4FD1),
    brandSoft: Color(0xFFE3EAFB),
    ok: Color(0xFF138A5B),
    okSoft: Color(0xFFDDF3E9),
    warn: Color(0xFFB4541A),
    warnSoft: Color(0xFFFBE9DD),
    muted: Color(0xFF5E6782),
    line: Color(0xFFD9DEE8),
    panel: Color(0xFFFFFFFF),
  );

  static const dark = AppColors(
    brand: Color(0xFF6F95FF),
    brandSoft: Color(0xFF1E2A4E),
    ok: Color(0xFF43C58F),
    okSoft: Color(0xFF153428),
    warn: Color(0xFFF0955A),
    warnSoft: Color(0xFF3A2518),
    muted: Color(0xFF9AA3BD),
    line: Color(0xFF2A3350),
    panel: Color(0xFF161D31),
  );

  static AppColors of(BuildContext context) => Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) =>
      other is AppColors && t > .5 ? other : this;
}

ThemeData buildTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final c = isLight ? AppColors.light : AppColors.dark;
  final ink = isLight ? const Color(0xFF16203A) : const Color(0xFFE8ECF6);
  final surface = isLight ? const Color(0xFFF7F8FB) : const Color(0xFF11172A);

  final scheme = ColorScheme.fromSeed(seedColor: c.brand, brightness: brightness).copyWith(
    primary: c.brand,
    onPrimary: isLight ? Colors.white : const Color(0xFF0E1322),
    secondaryContainer: c.brandSoft,
    onSecondaryContainer: c.brand,
    surface: surface,
    onSurface: ink,
    onSurfaceVariant: c.muted,
    outline: c.line,
    outlineVariant: c.line,
    error: c.warn,
  );

  final radius12 = BorderRadius.circular(12);
  final radius14 = BorderRadius.circular(14);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink),
    ),
    cardTheme: CardThemeData(
      color: c.panel,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        side: BorderSide(color: c.line),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.panel,
      border: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: c.line)),
      enabledBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: c.line)),
      focusedBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: c.brand, width: 2)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.panel,
      indicatorColor: c.brandSoft,
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1),
  );
}
