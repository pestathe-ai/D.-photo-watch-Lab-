import 'package:flutter/material.dart';

/// Colori del marchio Dom Studio (solo l'icona dell'app è rossa).
class Brand {
  static const blue = Color(0xFF1D3A8A);
  static const orange = Color(0xFFF28C38);
  static const paper = Color(0xFFFFF8F0);
  static const ink = Color(0xFF14213D);
}

/// Spaziature su griglia di 4/8 dp.
class Space {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Durate delle animazioni: brevi per i controlli, un po' più lunghe per
/// i cambi di pannello.
class Motion {
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 220);
}

const _brandFont = 'Sora';

TextTheme _withBrandHeadings(TextTheme t) => t.copyWith(
      headlineLarge: t.headlineLarge?.copyWith(fontFamily: _brandFont, fontWeight: FontWeight.w800),
      headlineMedium: t.headlineMedium?.copyWith(fontFamily: _brandFont, fontWeight: FontWeight.w800),
      headlineSmall: t.headlineSmall?.copyWith(fontFamily: _brandFont, fontWeight: FontWeight.w800),
      titleLarge: t.titleLarge?.copyWith(fontFamily: _brandFont, fontWeight: FontWeight.w600),
      titleMedium: t.titleMedium?.copyWith(fontFamily: _brandFont, fontWeight: FontWeight.w600),
    );

/// Tema dell'app (home e schermate normali), chiaro o scuro col sistema.
ThemeData buildTheme(Brightness b) {
  final light = b == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.blue,
    brightness: b,
    primary: light ? Brand.blue : const Color(0xFFB7C6F5),
    secondary: Brand.orange,
    surface: light ? Brand.paper : const Color(0xFF10141F),
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    textTheme: _withBrandHeadings(base.textTheme),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Tema dell'editor: grigio scuro neutro, come gli editor foto
/// professionali, così i colori della foto si giudicano senza dominanti.
ThemeData buildEditorTheme() {
  const canvas = Color(0xFF111316);
  const panel = Color(0xFF1B1E23);
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.blue,
    brightness: Brightness.dark,
    primary: const Color(0xFFB7C6F5),
    secondary: Brand.orange,
    surface: panel,
  ).copyWith(
    surfaceContainerLowest: canvas,
    surfaceContainerLow: panel,
    surfaceContainer: const Color(0xFF22262C),
    surfaceContainerHigh: const Color(0xFF2A2E35),
    surfaceContainerHighest: const Color(0xFF32363E),
    onSurfaceVariant: const Color(0xFFC4C7CF), // 9.8:1 su panel
    outlineVariant: const Color(0xFF3A3F47),
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: canvas,
    textTheme: _withBrandHeadings(base.textTheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: panel,
      indicatorColor: scheme.primary.withValues(alpha: 0.22),
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      inactiveTrackColor: scheme.outlineVariant,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
