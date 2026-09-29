import 'package:flutter/material.dart';

/// Toaster's visual language: a dark, dense, Blender-adjacent chrome with
/// restrained accents. One accent for tools, orange for selection.
class T {
  T._(); // coverage:ignore-line

  static const bg = Color(0xFF1B1B1F);
  static const panel = Color(0xFF232329);
  static const panelAlt = Color(0xFF2A2A31);
  static const border = Color(0xFF0E0E11);
  static const text = Color(0xFFD6D9DE);
  static const textDim = Color(0xFF8A8F98);
  static const accent = Color(0xFF4A7FB5);
  static const accentSoft = Color(0xFF3A5E85);
  static const selection = Color(0xFFFF8C42);
  static const danger = Color(0xFFC94C4C);

  static ThemeData theme() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          surface: panel,
          onSurface: text,
          surfaceContainerHighest: panelAlt,
          outline: border,
        ),
        dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
        textTheme: const TextTheme(
          bodySmall: TextStyle(fontSize: 11.5, color: text),
          bodyMedium: TextStyle(fontSize: 12.5, color: text),
          titleSmall: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: text),
        ),
        menuButtonTheme: MenuButtonThemeData(
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
            textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
          ),
        ),
        menuTheme: const MenuThemeData(
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(panelAlt),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
            padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
          ),
        ),
        sliderTheme: const SliderThemeData(
          trackHeight: 2,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: Color(0xFF1A1A1F),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          border: OutlineInputBorder(borderSide: BorderSide(color: border)),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: border)),
        ),
      );

  static TextStyle get hint => const TextStyle(fontSize: 11, color: textDim);

  static TextStyle get mono => const TextStyle(
        fontSize: 11,
        color: text,
        fontFamily: 'monospace',
      );
}
