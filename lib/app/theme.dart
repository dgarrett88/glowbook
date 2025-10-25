import 'package:flutter/material.dart';

ThemeData buildGlowTheme() {
  const surface = Color(0xFF0D0F1A);
  const panel = Color(0xFF14182A);
  const accent = Color(0xFF5DE0E6);
  const text = Color(0xFFE6E8EF);

  final colorScheme = const ColorScheme.dark().copyWith(
    surface: surface,
    primary: accent,
    secondary: Color(0xFFEE6DFA),
  );

  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: surface,
    useMaterial3: true,
    textTheme: const TextTheme(bodyMedium: TextStyle(color: text)),
    appBarTheme: const AppBarTheme(
      backgroundColor: panel,
      elevation: 0,
      centerTitle: false,
    ),
    sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.never),
  );
}
