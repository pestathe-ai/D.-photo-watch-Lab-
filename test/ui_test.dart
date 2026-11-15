import 'dart:math' as math;
import 'dart:typed_data';

import 'package:d_photo_watch_lab/core/codec.dart';
import 'package:d_photo_watch_lab/core/pipeline.dart';
import 'package:d_photo_watch_lab/ui/editor_screen.dart';
import 'package:d_photo_watch_lab/ui/home_screen.dart';
import 'package:d_photo_watch_lab/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Telefono piccolo con testo ingrandito: nessun elemento deve uscire dallo
/// schermo (Flutter segnala gli "overflow" come errori del test).
Widget _phone(Widget child, {double textScale = 1.3}) => MaterialApp(
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child,
        ),
      ),
    );

LoadedPhoto _photo() {
  const w = 240, h = 180;
  final rgb = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final d = math.sqrt((x - 120.0) * (x - 120) + (y - 90.0) * (y - 90));
      final v = d < 60 ? 40 : (d < 70 ? 150 : 200);
      final i = (y * w + x) * 3;
      rgb[i] = rgb[i + 1] = rgb[i + 2] = v;
    }
  }
  return loadPhoto(encodeJpeg(RgbImage(w, h, rgb)))!;
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1080, 1920);
    binding.platformDispatcher.views.first.devicePixelRatio = 3; // 360x640 dp
  });
  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  testWidgets('home: tutto visibile su telefono piccolo con testo grande',
      (tester) async {
    await tester.pumpWidget(_phone(const HomeScreen()));
    await tester.pump();
    expect(find.text('D. Photo Watch Lab'), findsOneWidget);
    expect(find.text('Scegli le foto'), findsOneWidget);
    // la firma è in fondo: ci si arriva scorrendo
    await tester.scrollUntilVisible(find.text("un'app Dom Studio"), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text("un'app Dom Studio"), findsOneWidget);
  });

  testWidgets('editor: tutte le schede senza overflow, con pulsante Prima',
      (tester) async {
    final photo = _photo();
    await tester.pumpWidget(_phone(EditorScreen(photo: photo)));
    await tester.pump();
    expect(find.text('Prima'), findsOneWidget);
    expect(find.text('Salva'), findsOneWidget);
    for (final tab in ['Luce', 'Quadrante', 'Sfondo', 'Auto']) {
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(milliseconds: 300));
    }
    // il confronto prima/dopo funziona tenendo premuto
    final gesture = await tester.startGesture(tester.getCenter(find.text('Prima')));
    await tester.pump();
    expect(find.text('Originale'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(find.text('Prima'), findsOneWidget);
  });

  testWidgets('editor: i cursori si azzerano con doppio tocco', (tester) async {
    final photo = _photo();
    await tester.pumpWidget(_phone(EditorScreen(photo: photo), textScale: 1));
    await tester.pump();
    await tester.tap(find.text('Luce').last);
    await tester.pump(const Duration(milliseconds: 300));
    // "Tono ricco" parte da 100 nello stile Ricco
    expect(find.text('100'), findsWidgets);
    await tester.tap(find.text('Tono ricco'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Tono ricco'));
    await tester.pump(const Duration(milliseconds: 400));
    final row = find.ancestor(of: find.text('Tono ricco'), matching: find.byType(Row));
    expect(find.descendant(of: row.first, matching: find.text('0')), findsOneWidget);
  });
}
