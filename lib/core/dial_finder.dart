import 'dart:math' as math;
import 'dart:typed_data';

import 'params.dart';
import 'pipeline.dart';

/// Risultato della ricerca del quadrante.
class DialGuess {
  final Dial dial;

  /// Quanto del contorno del cerchio è sostenuto dai bordi della foto
  /// (circa 0 = niente, oltre 1 = cerchio netto).
  final double confidence;

  const DialGuess(this.dial, this.confidence);

  bool get found => confidence >= kDialMinConfidence;
}

const double kDialMinConfidence = 0.6;

/// Cerca il quadrante: trasformata di Hough per cerchi sui bordi della foto
/// rimpicciolita (lato lungo 240 px). Trova il cerchio più netto (di solito
/// la cassa) e, se dentro c'è un cerchio concentrico abbastanza netto
/// (quadrante o lunetta), sceglie quello interno.
DialGuess findDial(RgbImage src) {
  final f = math.max(src.width, src.height) / 240.0;
  final w = math.max(8, (src.width / f).round());
  final h = math.max(8, (src.height / f).round());

  // luminosità media per cella (rimpicciolimento a media)
  final sum = Float32List(w * h);
  final cnt = Int32List(w * h);
  for (var y = 0; y < src.height; y++) {
    final sy = math.min(h - 1, (y * h) ~/ src.height);
    for (var x = 0; x < src.width; x++) {
      final sx = math.min(w - 1, (x * w) ~/ src.width);
      final j = (y * src.width + x) * 3;
      final l = (src.rgb[j] + src.rgb[j + 1] + src.rgb[j + 2]) / (3 * 255.0);
      sum[sy * w + sx] += l;
      cnt[sy * w + sx]++;
    }
  }
  var lum = Float32List(w * h);
  for (var i = 0; i < lum.length; i++) {
    lum[i] = cnt[i] > 0 ? sum[i] / cnt[i] : 0;
  }
  lum = _blur121(lum, w, h);

  // gradienti di Sobel
  final gx = Float32List(w * h), gy = Float32List(w * h), mag = Float32List(w * h);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      double p(int dx, int dy) => lum[(y + dy) * w + x + dx];
      final ax = (p(1, -1) + 2 * p(1, 0) + p(1, 1)) - (p(-1, -1) + 2 * p(-1, 0) + p(-1, 1));
      final ay = (p(-1, 1) + 2 * p(0, 1) + p(1, 1)) - (p(-1, -1) + 2 * p(0, -1) + p(1, -1));
      final i = y * w + x;
      gx[i] = ax;
      gy[i] = ay;
      mag[i] = math.sqrt(ax * ax + ay * ay);
    }
  }
  final thr = math.max(_percentile(mag, 88), 0.08);

  final mn = math.min(w, h);
  final rMin = math.max(3, (mn * 0.12).floor());
  final rMax = math.max(rMin + 1, (mn * 0.5).floor());
  final nr = rMax - rMin + 1;
  final acc = Float32List(nr * w * h);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final m = mag[i];
      if (m <= thr) continue;
      final dx = gx[i] / m, dy = gy[i] / m;
      for (var k = 0; k < nr; k++) {
        final r = rMin + k;
        for (var sgn = -1; sgn <= 1; sgn += 2) {
          final cx = (x + sgn * dx * r).round();
          final cy = (y + sgn * dy * r).round();
          if (cx < 0 || cy < 0 || cx >= w || cy >= h) continue;
          acc[(k * h + cy) * w + cx] += 1;
        }
      }
    }
  }

  // somma 3x3 nello spazio e normalizza per la circonferenza
  final score = Float32List(nr * w * h);
  for (var k = 0; k < nr; k++) {
    final norm = 1 / (2 * math.pi * (rMin + k));
    final base = k * w * h;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        double s = 0;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            s += acc[base + yy * w + xx];
          }
        }
        score[base + y * w + x] = s * norm;
      }
    }
  }

  var best = -1.0;
  var bk = 0, bx = w ~/ 2, by = h ~/ 2;
  for (var k = 0; k < nr; k++) {
    final base = k * w * h;
    for (var i = 0; i < w * h; i++) {
      if (score[base + i] > best) {
        best = score[base + i];
        bk = k;
        bx = i % w;
        by = i ~/ w;
      }
    }
  }
  if (best <= 0) return const DialGuess(Dial(), 0);
  final bestR = rMin + bk;

  // cerchio interno concentrico (quadrante dentro cassa o lunetta)
  var inner = -1.0;
  var ik = -1, ix = bx, iy = by;
  for (var k = 0; k < nr; k++) {
    final r = rMin + k;
    if (r > 0.93 * bestR || r < 0.55 * bestR) continue;
    final base = k * w * h;
    for (var y = math.max(0, by - 3); y <= math.min(h - 1, by + 3); y++) {
      for (var x = math.max(0, bx - 3); x <= math.min(w - 1, bx + 3); x++) {
        final s = score[base + y * w + x];
        if (s >= 0.45 * best && s > inner) {
          inner = s;
          ik = k;
          ix = x;
          iy = y;
        }
      }
    }
  }
  final useInner = ik >= 0;
  final r = useInner ? rMin + ik : bestR;
  final cx = useInner ? ix : bx;
  final cy = useInner ? iy : by;
  return DialGuess(
    Dial(cx: (cx + 0.5) / w, cy: (cy + 0.5) / h, r: r / mn),
    useInner ? inner : best,
  );
}

Float32List _blur121(Float32List src, int w, int h) {
  final tmp = Float32List(w * h), out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final l = src[y * w + math.max(0, x - 1)];
      final r = src[y * w + math.min(w - 1, x + 1)];
      tmp[y * w + x] = (l + 2 * src[y * w + x] + r) / 4;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final u = tmp[math.max(0, y - 1) * w + x];
      final d = tmp[math.min(h - 1, y + 1) * w + x];
      out[y * w + x] = (u + 2 * tmp[y * w + x] + d) / 4;
    }
  }
  return out;
}

double _percentile(Float32List v, double pct) {
  final s = Float32List.fromList(v)..sort();
  final i = ((s.length - 1) * pct / 100).round();
  return s[i];
}
