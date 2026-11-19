import 'package:flutter/material.dart';

const accentColors = <Color>[
  Color(0xFF6366F1), // indigo (v1 primary)
  Color(0xFF8B5CF6), // violet
  Color(0xFF10B981), // emerald
  Color(0xFFF97316), // orange
  Color(0xFFEC4899), // pink
  Color(0xFF0EA5E9), // sky
];

const accentNames = ['Indigo', 'Violet', 'Emerald', 'Sunset', 'Rose', 'Sky'];

const gold = Color(0xFFFFC107);
const silver = Color(0xFFB0BEC5);
const bronze = Color(0xFFCD7F32);

ThemeData buildTheme(Brightness brightness, int accentIndex) {
  final seed = accentColors[accentIndex.clamp(0, accentColors.length - 1)];
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  final isDark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? const Color(0xFF0F1117) : const Color(0xFFF5F6FA),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? const Color(0xFF1A1D27) : Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: scheme.onSurface,
        letterSpacing: -0.5,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark ? const Color(0xFF151821) : Colors.white,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF242836) : const Color(0xFFF1F2F6),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? const Color(0xFF1A1D27) : Colors.white,
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? const Color(0xFF1A1D27) : Colors.white,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
