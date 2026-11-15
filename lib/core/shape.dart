import 'dart:math' as math;
import 'dart:typed_data';

import 'pipeline.dart' show boxBlur;

/// Contorno del quadrante di qualsiasi forma (tondo, rettangolare, tonneau):
/// poligono convesso con i vertici in frazione di larghezza/altezza (0..1).
class DialShape {
  /// x0, y0, x1, y1, ...
  final List<double> pts;

  const DialShape(this.pts);

  int get length => pts.length ~/ 2;

  /// Baricentro dell'area (non dei soli vertici).
  ({double x, double y}) get centroid {
    double a = 0, cx = 0, cy = 0;
    for (var i = 0; i < length; i++) {
      final j = (i + 1) % length;
      final x0 = pts[2 * i], y0 = pts[2 * i + 1];
      final x1 = pts[2 * j], y1 = pts[2 * j + 1];
      final c = x0 * y1 - x1 * y0;
      a += c;
      cx += (x0 + x1) * c;
      cy += (y0 + y1) * c;
    }
    if (a.abs() < 1e-9) {
      double sx = 0, sy = 0;
      for (var i = 0; i < length; i++) {
        sx += pts[2 * i];
        sy += pts[2 * i + 1];
      }
      return (x: sx / length, y: sy / length);
    }
    return (x: cx / (3 * a), y: cy / (3 * a));
  }

  /// Spostata di (dx, dy) e ingrandita di [scale] attorno al baricentro.
  DialShape transformed(double dx, double dy, double scale) {
    final c = centroid;
    final out = List<double>.filled(pts.length, 0);
    for (var i = 0; i < length; i++) {
      out[2 * i] = (c.x + (pts[2 * i] - c.x) * scale + dx).clamp(0.0, 1.0);
      out[2 * i + 1] = (c.y + (pts[2 * i + 1] - c.y) * scale + dy).clamp(0.0, 1.0);
    }
    return DialShape(out);
  }

  /// Area in frazione dell'immagine.
  double get area {
    double a = 0;
    for (var i = 0; i < length; i++) {
      final j = (i + 1) % length;
      a += pts[2 * i] * pts[2 * j + 1] - pts[2 * j] * pts[2 * i + 1];
    }
    return a.abs() / 2;
  }

  /// Maschera morbida 0..1 alla misura [w]x[h]; bordo sfumato di circa
  /// [feather] (in frazione del lato corto).
  Float32List rasterize(int w, int h, {double feather = 0.012}) {
    final m = Float32List(w * h);
    final n = length;
    if (n < 3) return m;
    final xs = <double>[];
    for (var y = 0; y < h; y++) {
      final fy = y + 0.5;
      xs.clear();
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        final y0 = pts[2 * i + 1] * h, y1 = pts[2 * j + 1] * h;
        if ((y0 <= fy && y1 > fy) || (y1 <= fy && y0 > fy)) {
          final x0 = pts[2 * i] * w, x1 = pts[2 * j] * w;
          xs.add(x0 + (fy - y0) / (y1 - y0) * (x1 - x0));
        }
      }
      xs.sort();
      for (var k = 0; k + 1 < xs.length; k += 2) {
        final a = math.max(0, xs[k].round());
        final b = math.min(w, xs[k + 1].round());
        for (var x = a; x < b; x++) {
          m[y * w + x] = 1;
        }
      }
    }
    final r = (feather * math.min(w, h)).round();
    if (r < 1) return m;
    return boxBlur(boxBlur(m, w, h, r), w, h, r);
  }
}

/// Inviluppo convesso (monotone chain) di punti interi; restituisce i
/// vertici in senso antiorario.
List<math.Point<int>> convexHull(List<math.Point<int>> p) {
  if (p.length < 3) return List.of(p);
  final s = List.of(p)
    ..sort((a, b) => a.x != b.x ? a.x - b.x : a.y - b.y);
  int cross(math.Point<int> o, math.Point<int> a, math.Point<int> b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  final lower = <math.Point<int>>[];
  for (final q in s) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, q) <= 0) {
      lower.removeLast();
    }
    lower.add(q);
  }
  final upper = <math.Point<int>>[];
  for (final q in s.reversed) {
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, q) <= 0) {
      upper.removeLast();
    }
    upper.add(q);
  }
  return [...lower.sublist(0, lower.length - 1), ...upper.sublist(0, upper.length - 1)];
}

/// Contorno convesso di una maschera binaria (w x h) come [DialShape].
/// Usa solo i pixel di bordo di ogni riga (veloce anche su maschere grandi).
DialShape? shapeFromMask(Uint8List mask, int w, int h) {
  final pts = <math.Point<int>>[];
  for (var y = 0; y < h; y++) {
    var first = -1, last = -1;
    for (var x = 0; x < w; x++) {
      if (mask[y * w + x] != 0) {
        if (first < 0) first = x;
        last = x;
      }
    }
    if (first >= 0) {
      pts.add(math.Point(first, y));
      pts.add(math.Point(last + 1, y));
      pts.add(math.Point(first, y + 1));
      pts.add(math.Point(last + 1, y + 1));
    }
  }
  if (pts.length < 3) return null;
  final hull = convexHull(pts);
  if (hull.length < 3) return null;
  final out = <double>[];
  for (final q in hull) {
    out
      ..add(q.x / w)
      ..add(q.y / h);
  }
  return DialShape(out);
}
