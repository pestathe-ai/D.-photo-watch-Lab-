import 'dart:math' as math;
import 'dart:typed_data';

import 'package:d_photo_watch_lab/core/codec.dart';
import 'package:d_photo_watch_lab/core/params.dart';
import 'package:d_photo_watch_lab/core/pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// Foto finta: sfondo carta grigio-giallo, cassa, quadrante blu scuro,
/// indici chiari, puntini di polvere, rumore e dominante gialla.
const int W = 800, H = 600;
const dustSpots = [
  [330, 250],
  [470, 330],
  [400, 380],
  [350, 340],
];

RgbImage synthetic({bool dust = true}) {
  final rnd = math.Random(1);
  final rgb = Uint8List(W * H * 3);
  const cx = W / 2, cy = H / 2;
  for (var y = 0; y < H; y++) {
    for (var x = 0; x < W; x++) {
      final d = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
      double r, g, b;
      if (d < 180) {
        r = 0.10;
        g = 0.12;
        b = 0.19;
        // indice delle 12: barretta verticale larga 6 px
        if ((x - cx).abs() <= 3 && y > cy - 160 && y < cy - 120) {
          r = g = b = 0.85;
        }
        // scritta finta: riga orizzontale sottile (2 px)
        if (y >= cy + 60 && y <= cy + 61 && (x - cx).abs() < 40) {
          r = g = b = 0.8;
        }
      } else if (d < 215) {
        r = g = b = 0.47;
      } else {
        r = 0.78;
        g = 0.77;
        b = 0.71;
      }
      final i = (y * W + x) * 3;
      double n() => (rnd.nextDouble() - 0.5) * 0.06;
      rgb[i] = _c((r + n()) * 1.0);
      rgb[i + 1] = _c((g + n()) * 0.97);
      rgb[i + 2] = _c((b + n()) * 0.88);
    }
  }
  if (dust) {
    for (final s in dustSpots) {
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final i = ((s[1] + dy) * W + s[0] + dx) * 3;
          rgb[i] = rgb[i + 1] = rgb[i + 2] = 215;
        }
      }
    }
  }
  return RgbImage(W, H, rgb);
}

int _c(double v) => (v * 255).round().clamp(0, 255);

double lumAt(Planes p, int x, int y) {
  final i = y * p.w + x;
  return 0.299 * p.r[i] + 0.587 * p.g[i] + 0.114 * p.b[i];
}

const dial = Dial(cx: 0.5, cy: 0.5, r: 180 / 600);

void main() {
  test('la sfocatura a scatola conserva un colore uniforme', () {
    final src = Float32List(30 * 20)..fillRange(0, 600, 0.4);
    final out = boxBlur(src, 30, 20, 4);
    for (final v in out) {
      expect(v, closeTo(0.4, 1e-5));
    }
  });

  test('il filtro guidato liscia il rumore ma tiene il bordo', () {
    const w = 40, h = 10;
    final rnd = math.Random(2);
    final src = Float32List(w * h);
    for (var i = 0; i < src.length; i++) {
      src[i] = (i % w < 20 ? 0.2 : 0.8) + (rnd.nextDouble() - 0.5) * 0.05;
    }
    final out = guidedSelf(src, w, h, 3, 0.01);
    expect(out[5 * w + 19], lessThan(0.35)); // lato scuro resta scuro
    expect(out[5 * w + 20], greaterThan(0.65)); // lato chiaro resta chiaro
  });

  test('l\'analisi riconosce la dominante gialla', () {
    final a = analyze(Planes.fromRgb(synthetic()));
    expect(a.gainB, greaterThan(a.gainR));
    expect(a.black, lessThan(a.white));
  });

  test('senza ritocco la foto resta uguale', () {
    final src = synthetic();
    final out = enhance(src, Analysis.neutral, EnhanceParams.none);
    final a = Planes.fromRgb(src);
    for (final xy in [
      [10, 10],
      [400, 300],
      [400, 150]
    ]) {
      expect(lumAt(out, xy[0], xy[1]), closeTo(lumAt(a, xy[0], xy[1]), 0.01));
    }
  });

  group('migliora in un tocco', () {
    late Planes out;
    late Planes before;
    setUpAll(() {
      final src = synthetic();
      before = Planes.fromRgb(src);
      out = enhance(src, analyze(before), EnhanceParams.auto.withDial(dial));
    });

    test('toglie i puntini di polvere dal quadrante', () {
      for (final s in dustSpots) {
        expect(lumAt(before, s[0], s[1]), greaterThan(0.6));
        expect(lumAt(out, s[0], s[1]), lessThan(0.3),
            reason: 'puntino in ${s[0]},${s[1]}');
      }
    });

    test('lascia intatti indici e scritte', () {
      expect(lumAt(out, 400, 160), greaterThan(0.7)); // indice delle 12
      expect(lumAt(out, 400, 360), greaterThan(0.5)); // riga sottile
    });

    test('porta lo sfondo chiaro al bianco', () {
      expect(lumAt(out, 30, 30), greaterThan(0.93));
      expect(lumAt(out, 770, 570), greaterThan(0.93));
    });

    test('il quadrante resta scuro (lo sfondo bianco non lo tocca)', () {
      expect(lumAt(out, 450, 260), lessThan(0.3));
    });

    test('riduce il rumore sul quadrante', () {
      double sd(Planes p) {
        final v = <double>[];
        for (var y = 280; y < 300; y++) {
          for (var x = 300; x < 330; x++) {
            v.add(lumAt(p, x, y));
          }
        }
        final m = v.reduce((a, b) => a + b) / v.length;
        return math.sqrt(
            v.map((e) => (e - m) * (e - m)).reduce((a, b) => a + b) / v.length);
      }

      expect(sd(out), lessThan(sd(before)));
    });
  });

  test('ritaglio quadrato centrato sul quadrante', () {
    final out = enhance(synthetic(dust: false), Analysis.neutral,
        EnhanceParams.none.copyWith(square: true, dialOn: true, dial: dial));
    expect(out.w, 600);
    expect(out.h, 600);
    // il centro del ritaglio è il centro del quadrante (scuro)
    expect(lumAt(out, 300, 300), lessThan(0.3));
  });

  test('codifica e decodifica JPG mantengono le misure', () {
    final jpg = encodeJpeg(synthetic(dust: false));
    final back = decodeToRgb(jpg, 4000)!;
    expect(back.width, W);
    expect(back.height, H);
    final small = decodeToRgb(jpg, 400)!;
    expect(small.width, 400);
    expect(small.height, 300);
  });

  test('caricamento completo e render', () {
    final photo = loadPhoto(encodeJpeg(synthetic()))!;
    expect(photo.preview.width, W);
    final jpg = renderJpeg(photo.preview, photo.analysis,
        EnhanceParams.auto.withDial(dial));
    expect(jpg.length, greaterThan(1000));
  });
}
