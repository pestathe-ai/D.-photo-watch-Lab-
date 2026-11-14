import 'package:flutter/material.dart';

/// Colori del marchio Dom Studio.
class Brand {
  static const blue = Color(0xFF1D3A8A);
  static const orange = Color(0xFFF28C38);
  static const paper = Color(0xFFFFF8F0);
  static const ink = Color(0xFF14213D);
}

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.blue,
    brightness: b,
    primary: b == Brightness.light ? Brand.blue : const Color(0xFFB7C6F5),
    secondary: Brand.orange,
    surface: b == Brightness.light ? Brand.paper : const Color(0xFF10141F),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
  );
}
