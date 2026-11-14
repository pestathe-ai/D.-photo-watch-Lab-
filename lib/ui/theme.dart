import 'package:flutter/material.dart';

/// Colori dell'app: famiglia Dom Studio, in versione rossa.
class Brand {
  static const red = Color(0xFFB3261E);
  static const blue = Color(0xFF1D3A8A);
  static const orange = Color(0xFFF28C38);
  static const paper = Color(0xFFFFF8F0);
  static const ink = Color(0xFF14213D);
}

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.red,
    brightness: b,
    primary: b == Brightness.light ? Brand.red : const Color(0xFFFFB4AB),
    secondary: Brand.orange,
    surface: b == Brightness.light ? Brand.paper : const Color(0xFF1A1111),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
  );
}
