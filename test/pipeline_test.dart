import 'dart:math' as math;
import 'dart:typed_data';

import 'package:d_photo_watch_lab/core/codec.dart';
import 'package:d_photo_watch_lab/core/dial_finder.dart';
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

/// Orologio semplice in posizione e misura qualsiasi (cassa rc, quadrante rd).
RgbImage drawWatch(int w, int h, double cx, double cy, double rc, double rd) {
  final rnd = math.Random(5);
  final rgb = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final d = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
      final v = d < rd ? 0.12 : (d < rc ? 0.47 : 0.78);
      final i = (y * w + x) * 3;
      final n = (rnd.nextDouble() - 0.5) * 0.06;
      rgb[i] = _c(v + n);
      rgb[i + 1] = _c((v + n) * 0.97);
      rgb[i + 2] = _c((v + n) * 0.9);
    }
  }
  return RgbImage(w, h, rgb);
}

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

  group('trova il quadrante', () {
    test('al centro, dentro la cassa', () {
      final g = findDial(synthetic());
      expect(g.found, isTrue);
      expect(g.dial.cx, closeTo(0.5, 0.02));
      expect(g.dial.cy, closeTo(0.5, 0.02));
      // il quadrante (r 180), non la cassa (r 215)
      expect(g.dial.r, closeTo(180 / 600, 0.02));
    });

    test('decentrato e in verticale', () {
      final g = findDial(drawWatch(600, 800, 330, 380, 230, 190));
      expect(g.found, isTrue);
      expect(g.dial.cx, closeTo(330 / 600, 0.02));
      expect(g.dial.cy, closeTo(380 / 800, 0.02));
      expect(g.dial.r, closeTo(190 / 600, 0.02));
    });

    test('su una foto senza orologio non trova niente', () {
      final rgb = Uint8List(W * H * 3);
      final rnd = math.Random(4);
      for (var i = 0; i < rgb.length; i++) {
        rgb[i] = 170 + rnd.nextInt(10);
      }
      expect(findDial(RgbImage(W, H, rgb)).found, isFalse);
    });
  });

  test('il colore automatico non raffredda del tutto la luce calda', () {
    final out = enhance(synthetic(dust: false), analyze(Planes.fromRgb(synthetic())),
        EnhanceParams.none.copyWith(autoColor: true));
    const i = 10 * W + 10; // carta dello sfondo, con luce calda
    expect(out.r[i], greaterThan(out.b[i] + 0.02));
  });

  test('ammorbidisce un graffietto ma lascia nitido l\'indice', () {
    // quadrante uniforme con un graffio sottile e poco contrastato
    final img = synthetic(dust: false);
    for (var x = 330; x < 380; x++) {
      final i = (330 * W + x) * 3;
      img.rgb[i] += 18;
      img.rgb[i + 1] += 18;
      img.rgb[i + 2] += 18;
    }
    const base = EnhanceParams(
        autoColor: false, dialOn: true, dial: dial);
    final soft = enhance(img, Analysis.neutral, base.copyWith(smooth: 1));
    final plain = enhance(img, Analysis.neutral, base);
    // contrasto medio del graffio lungo la sua lunghezza
    double scratch(Planes p) {
      double s = 0;
      for (var x = 340; x < 370; x++) {
        s += lumAt(p, x, 330) - (lumAt(p, x, 324) + lumAt(p, x, 336)) / 2;
      }
      return s / 30;
    }
    expect(scratch(soft), lessThan(scratch(plain) * 0.6));
    // l'indice delle 12 resta chiaro e netto
    expect(lumAt(soft, 400, 160), greaterThan(0.75));
    expect(lumAt(soft, 400, 160) - lumAt(soft, 410, 160), greaterThan(0.5));
  });

  test('con lo scontorno IA lo sfondo schiarisce, l\'orologio no', () {
    final src = synthetic(dust: false);
    // maschera: orologio = cerchio della cassa
    final m = Uint8List(W * H);
    for (var y = 0; y < H; y++) {
      for (var x = 0; x < W; x++) {
        final d = math.sqrt((x - 400) * (x - 400) + (y - 300) * (y - 300));
        m[y * W + x] = d < 215 ? 255 : 0;
      }
    }
    // sfondo scuro e colorato: senza IA non verrebbe toccato
    for (var i = 0; i < W * H; i++) {
      if (m[i] == 0) {
        src.rgb[i * 3] = 90;
        src.rgb[i * 3 + 1] = 120;
        src.rgb[i * 3 + 2] = 80;
      }
    }
    final p = EnhanceParams.none.copyWith(background: 1, dialOn: false);
    final withAi = enhance(src, Analysis.neutral, p, subject: m);
    final noAi = enhance(src, Analysis.neutral, p);
    expect(lumAt(withAi, 20, 20), greaterThan(0.75));
    expect(lumAt(noAi, 20, 20), lessThan(0.5));
    // la cassa (dentro la maschera) resta com'era
    expect(lumAt(withAi, 205, 300), closeTo(lumAt(noAi, 205, 300), 0.01));
  });

  test('intensità zero = solo colore automatico', () {
    final p = EnhanceParams.auto.withDial(dial).copyWith(intensity: 0).effective();
    expect(p.sharpen, 0);
    expect(p.smooth, 0);
    expect(p.background, 0);
    expect(p.autoColor, isTrue);
    expect(p.dialOn, isTrue);
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

  test('serie: preparazione ed esportazione di una foto', () {
    final jpg = encodeJpeg(synthetic());
    final prep = prepareBatchItem(jpg)!;
    expect(prep.dialGuess.found, isTrue);
    expect(prep.params.dialOn, isTrue);
    expect(prep.previewW, W);
    final out = runFileRenderJob(
        FileRenderJob(jpg, kExportMaxSide, prep.analysis, prep.params))!;
    final back = decodeToRgb(out, 4000)!;
    expect(back.width, W);
  });

  test('caricamento completo e render', () {
    final photo = loadPhoto(encodeJpeg(synthetic()))!;
    expect(photo.preview.width, W);
    final jpg = renderJpeg(photo.preview, photo.analysis,
        EnhanceParams.auto.withDial(dial));
    expect(jpg.length, greaterThan(1000));
  });
}
