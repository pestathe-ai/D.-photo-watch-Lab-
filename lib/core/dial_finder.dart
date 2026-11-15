import 'dart:math' as math;
import 'dart:typed_data';

import 'params.dart';
import 'shape.dart';
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

// ---------------------------------------------------------------------------
// Quadrante di qualsiasi forma

/// Cerca il quadrante come la zona grande, liscia, convessa e di colore
/// uniforme vicino al centro della foto, che non tocca i bordi. Funziona con
/// quadranti tondi, rettangolari e tonneau. Provato sulle foto reali
/// dell'utente (Citizen rettangolare: 7 su 7).
DialShape? findDialShape(RgbImage src) {
  const side = 320;
  final f = math.max(src.width, src.height) / side;
  final w = math.max(8, (src.width / f).round());
  final h = math.max(8, (src.height / f).round());
  final n = w * h;

  // media per cella, per canale
  final sr = Float32List(n), sg = Float32List(n), sb = Float32List(n);
  final cnt = Int32List(n);
  for (var y = 0; y < src.height; y++) {
    final cy = math.min(h - 1, (y * h) ~/ src.height);
    for (var x = 0; x < src.width; x++) {
      final cx = math.min(w - 1, (x * w) ~/ src.width);
      final j = (y * src.width + x) * 3;
      final i = cy * w + cx;
      sr[i] += src.rgb[j] / 255.0;
      sg[i] += src.rgb[j + 1] / 255.0;
      sb[i] += src.rgb[j + 2] / 255.0;
      cnt[i]++;
    }
  }
  for (var i = 0; i < n; i++) {
    final c = math.max(1, cnt[i]);
    sr[i] /= c;
    sg[i] /= c;
    sb[i] /= c;
  }
  final r = boxBlur(sr, w, h, 1), g = boxBlur(sg, w, h, 1), b = boxBlur(sb, w, h, 1);
  final c0 = Float32List(n), c1 = Float32List(n), c2 = Float32List(n);
  for (var i = 0; i < n; i++) {
    c0[i] = (r[i] + g[i] + b[i]) / 3;
    c1[i] = r[i] - g[i];
    c2[i] = (r[i] + g[i]) / 2 - b[i];
  }
  final grad = Float32List(n);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final xl = math.max(0, x - 1), xr = math.min(w - 1, x + 1);
      final yu = math.max(0, y - 1), yd = math.min(h - 1, y + 1);
      final gx = (c0[y * w + xr] - c0[y * w + xl]) / math.max(1, xr - xl);
      final gy = (c0[yd * w + x] - c0[yu * w + x]) / math.max(1, yd - yu);
      grad[y * w + x] = math.sqrt(gx * gx + gy * gy);
    }
  }
  final gthr = math.max(_percentile(grad, 85), 0.03);

  double dist(int i, double r0, double r1, double r2) =>
      (c0[i] - r0).abs() + (c1[i] - r1).abs() + (c2[i] - r2).abs();

  final queue = Int32List(n);
  Uint8List grow(int seed, double tol) {
    final m = Uint8List(n);
    final r0 = c0[seed], r1 = c1[seed], r2 = c2[seed];
    var head = 0, tail = 0;
    queue[tail++] = seed;
    m[seed] = 1;
    while (head < tail) {
      final i = queue[head++];
      final x = i % w, y = i ~/ w;
      for (var k = 0; k < 4; k++) {
        int xx = x, yy = y;
        if (k == 0) xx++;
        if (k == 1) xx--;
        if (k == 2) yy++;
        if (k == 3) yy--;
        if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
        final j = yy * w + xx;
        if (m[j] != 0) continue;
        if (grad[j] < gthr && dist(j, r0, r1, r2) < tol) {
          m[j] = 1;
          queue[tail++] = j;
        }
      }
    }
    return m;
  }

  _Cand? best;
  for (var a = 0; a < 7; a++) {
    for (var bI = 0; bI < 7; bI++) {
      final sy = ((0.3 + 0.4 * a / 6) * h).floor().clamp(0, h - 1);
      final sx = ((0.3 + 0.4 * bI / 6) * w).floor().clamp(0, w - 1);
      final seed = sy * w + sx;
      if (grad[seed] >= gthr) continue;
      for (final tol in const [0.10, 0.16]) {
        final reg = grow(seed, tol);
        final area = _count(reg) / n;
        if (area < 0.01 || area > 0.5) continue;
        if (_touchesBorder(reg, w, h)) continue;
        final c = _close(reg, w, h, 2);
        final hull = _hullOf(c, w, h);
        if (hull == null) continue;
        final hm = _fill(hull, w, h);
        final hmCount = _count(hm);
        final ha = hmCount / n;
        final solidity = _count(c) / math.max(1, hmCount);
        double tex = 0;
        var rc = 0;
        double mx = 0, my = 0;
        for (var i = 0; i < n; i++) {
          if (reg[i] != 0) {
            tex += grad[i];
            rc++;
          }
          if (hm[i] != 0) {
            mx += i % w;
            my += i ~/ w;
          }
        }
        tex /= math.max(1, rc);
        final cx = mx / math.max(1, hmCount) / w, cy = my / math.max(1, hmCount) / h;
        final central = 1 -
            math.min(1.0, math.sqrt((cx - 0.5) * (cx - 0.5) + (cy - 0.5) * (cy - 0.5)) / 0.5);
        final score = math.sqrt(ha) *
            math.pow(solidity, 3) *
            (0.5 + central) /
            (1 + 20 * tex);
        if (best == null || score > best.score) {
          best = _Cand(score, hm, hull, tol);
        }
      }
    }
  }
  if (best == null) return null;

  // unisce i pezzi del quadrante separati dalle lancette
  var hm = best.mask;
  var hull = best.hull;
  final hmCount = _count(hm);
  double r0 = 0, r1 = 0, r2 = 0;
  var k = 0;
  double mx = 0, my = 0;
  for (var i = 0; i < n; i++) {
    if (hm[i] == 0) continue;
    mx += i % w;
    my += i ~/ w;
    if (grad[i] < gthr) {
      r0 += c0[i];
      r1 += c1[i];
      r2 += c2[i];
      k++;
    }
  }
  if (k > 0) {
    r0 /= k;
    r1 /= k;
    r2 /= k;
    final cx = mx / hmCount, cy = my / hmCount;
    final bigHull = [
      for (final p in hull)
        math.Point<int>((cx + (p.x - cx) * 1.25).round(), (cy + (p.y - cy) * 1.25).round())
    ];
    final big = _fill(bigHull, w, h);
    final sim = Uint8List(n);
    for (var i = 0; i < n; i++) {
      if (big[i] != 0 && grad[i] < gthr && dist(i, r0, r1, r2) < best.tol * 1.1) sim[i] = 1;
    }
    final near = _close(hm, w, h, 3);
    final keep = Uint8List.fromList(hm);
    final seen = Uint8List(n);
    for (var s = 0; s < n; s++) {
      if (sim[s] == 0 || seen[s] != 0) continue;
      // componente connessa
      var head = 0, tail = 0;
      queue[tail++] = s;
      seen[s] = 1;
      var touches = false;
      while (head < tail) {
        final i = queue[head++];
        if (near[i] != 0) touches = true;
        final x = i % w, y = i ~/ w;
        for (var d = 0; d < 4; d++) {
          int xx = x, yy = y;
          if (d == 0) xx++;
          if (d == 1) xx--;
          if (d == 2) yy++;
          if (d == 3) yy--;
          if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
          final j = yy * w + xx;
          if (sim[j] != 0 && seen[j] == 0) {
            seen[j] = 1;
            queue[tail++] = j;
          }
        }
      }
      if (touches && tail >= 0.02 * hmCount) {
        for (var q = 0; q < tail; q++) {
          keep[queue[q]] = 1;
        }
      }
    }
    final c = _close(keep, w, h, 2);
    if (!_touchesBorder(c, w, h)) {
      final h2 = _hullOf(c, w, h);
      if (h2 != null) {
        final m2 = _fill(h2, w, h);
        if (_count(m2) <= 2.2 * hmCount) {
          hm = m2;
          hull = h2;
        }
      }
    }
  }
  final pts = <double>[];
  for (final p in hull) {
    pts
      ..add((p.x + 0.5) / w)
      ..add((p.y + 0.5) / h);
  }
  return DialShape(pts);
}

class _Cand {
  final double score;
  final Uint8List mask;
  final List<math.Point<int>> hull;
  final double tol;
  _Cand(this.score, this.mask, this.hull, this.tol);
}

int _count(Uint8List m) {
  var c = 0;
  for (final v in m) {
    if (v != 0) c++;
  }
  return c;
}

bool _touchesBorder(Uint8List m, int w, int h) {
  for (var x = 0; x < w; x++) {
    if (m[x] != 0 || m[(h - 1) * w + x] != 0) return true;
  }
  for (var y = 0; y < h; y++) {
    if (m[y * w] != 0 || m[y * w + w - 1] != 0) return true;
  }
  return false;
}

/// Chiusura morfologica con un quadrato di raggio [r].
Uint8List _close(Uint8List m, int w, int h, int r) {
  final f = Float32List(w * h);
  for (var i = 0; i < f.length; i++) {
    f[i] = m[i].toDouble();
  }
  final d = boxBlur(f, w, h, r);
  for (var i = 0; i < d.length; i++) {
    d[i] = d[i] > 1e-3 ? 1 : 0;
  }
  final e = boxBlur(d, w, h, r);
  final out = Uint8List(w * h);
  for (var i = 0; i < out.length; i++) {
    out[i] = e[i] > 1 - 1e-3 ? 1 : 0;
  }
  return out;
}

List<math.Point<int>>? _hullOf(Uint8List m, int w, int h) {
  final pts = <math.Point<int>>[];
  for (var y = 0; y < h; y++) {
    var first = -1, last = -1;
    for (var x = 0; x < w; x++) {
      if (m[y * w + x] != 0) {
        if (first < 0) first = x;
        last = x;
      }
    }
    if (first >= 0) {
      pts.add(math.Point(first, y));
      if (last != first) pts.add(math.Point(last, y));
    }
  }
  if (pts.length < 3) return null;
  final hull = convexHull(pts);
  return hull.length < 3 ? null : hull;
}

/// Riempie un poligono convesso in coordinate pixel (bordo compreso).
Uint8List _fill(List<math.Point<int>> poly, int w, int h) {
  final out = Uint8List(w * h);
  final n = poly.length;
  for (var y = 0; y < h; y++) {
    double lo = double.infinity, hi = -double.infinity;
    for (var i = 0; i < n; i++) {
      final a = poly[i], b = poly[(i + 1) % n];
      final y0 = a.y.toDouble(), y1 = b.y.toDouble();
      if ((y < math.min(y0, y1)) || (y > math.max(y0, y1))) continue;
      if (y0 == y1) {
        lo = math.min(lo, math.min(a.x, b.x).toDouble());
        hi = math.max(hi, math.max(a.x, b.x).toDouble());
      } else {
        final x = a.x + (y - y0) / (y1 - y0) * (b.x - a.x);
        lo = math.min(lo, x);
        hi = math.max(hi, x);
      }
    }
    if (lo > hi) continue;
    final x0 = math.max(0, lo.round()), x1 = math.min(w - 1, hi.round());
    for (var x = x0; x <= x1; x++) {
      out[y * w + x] = 1;
    }
  }
  return out;
}
