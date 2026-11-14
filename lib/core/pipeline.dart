import 'dart:math' as math;
import 'dart:typed_data';

import 'params.dart';

/// Foto RGB 8 bit compatta (3 byte per pixel), usata per conservare
/// l'originale e passarlo agli isolate.
class RgbImage {
  final int width;
  final int height;
  final Uint8List rgb;

  RgbImage(this.width, this.height, this.rgb)
      : assert(rgb.length == width * height * 3);
}

/// Foto a canali separati in virgola mobile (0..1), usata durante il calcolo.
class Planes {
  final int w;
  final int h;
  final Float32List r;
  final Float32List g;
  final Float32List b;

  Planes(this.w, this.h, this.r, this.g, this.b);

  factory Planes.fromRgb(RgbImage im) {
    final n = im.width * im.height;
    final r = Float32List(n), g = Float32List(n), b = Float32List(n);
    const k = 1 / 255.0;
    for (var i = 0, j = 0; i < n; i++, j += 3) {
      r[i] = im.rgb[j] * k;
      g[i] = im.rgb[j + 1] * k;
      b[i] = im.rgb[j + 2] * k;
    }
    return Planes(im.width, im.height, r, g, b);
  }

  RgbImage toRgb() {
    final n = w * h;
    final out = Uint8List(n * 3);
    for (var i = 0, j = 0; i < n; i++, j += 3) {
      out[j] = _to8(r[i]);
      out[j + 1] = _to8(g[i]);
      out[j + 2] = _to8(b[i]);
    }
    return RgbImage(w, h, out);
  }

  static int _to8(double v) {
    final x = (v * 255 + 0.5).floor();
    return x < 0 ? 0 : (x > 255 ? 255 : x);
  }

  Float32List luminance() {
    final n = w * h;
    final l = Float32List(n);
    for (var i = 0; i < n; i++) {
      l[i] = 0.299 * r[i] + 0.587 * g[i] + 0.114 * b[i];
    }
    return l;
  }
}

// ---------------------------------------------------------------------------
// Filtri di base

/// Sfocatura a scatola di raggio [rad] (bordi ripetuti), O(n) per pixel.
Float32List boxBlur(Float32List src, int w, int h, int rad) {
  if (rad < 1) return Float32List.fromList(src);
  final tmp = Float32List(w * h);
  final out = Float32List(w * h);
  final inv = 1.0 / (2 * rad + 1);
  // orizzontale
  for (var y = 0; y < h; y++) {
    final row = y * w;
    var acc = src[row] * (rad + 1);
    for (var i = 1; i <= rad; i++) {
      acc += src[row + math.min(i, w - 1)];
    }
    for (var x = 0; x < w; x++) {
      tmp[row + x] = acc * inv;
      final add = math.min(x + rad + 1, w - 1);
      final sub = math.max(x - rad, 0);
      acc += src[row + add] - src[row + sub];
    }
  }
  // verticale
  for (var x = 0; x < w; x++) {
    var acc = tmp[x] * (rad + 1);
    for (var i = 1; i <= rad; i++) {
      acc += tmp[math.min(i, h - 1) * w + x];
    }
    for (var y = 0; y < h; y++) {
      out[y * w + x] = acc * inv;
      final add = math.min(y + rad + 1, h - 1);
      final sub = math.max(y - rad, 0);
      acc += tmp[add * w + x] - tmp[sub * w + x];
    }
  }
  return out;
}

/// Approssimazione di una sfocatura gaussiana (tre passate a scatola).
Float32List gaussBlur(Float32List src, int w, int h, int rad) =>
    boxBlur(boxBlur(boxBlur(src, w, h, rad), w, h, rad), w, h, rad);

/// Filtro guidato con sé stesso come guida: liscia le zone piatte e
/// conserva i bordi (niente aloni).
Float32List guidedSelf(Float32List p, int w, int h, int rad, double eps) {
  final n = w * h;
  final pp = Float32List(n);
  for (var i = 0; i < n; i++) {
    pp[i] = p[i] * p[i];
  }
  final m = boxBlur(p, w, h, rad);
  final mm = boxBlur(pp, w, h, rad);
  final a = Float32List(n), b = Float32List(n);
  for (var i = 0; i < n; i++) {
    final v = mm[i] - m[i] * m[i];
    final ai = v / (v + eps);
    a[i] = ai;
    b[i] = m[i] - ai * m[i];
  }
  final ma = boxBlur(a, w, h, rad);
  final mb = boxBlur(b, w, h, rad);
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = ma[i] * p[i] + mb[i];
  }
  return out;
}

/// Percentile (0..100) di un insieme di valori nell'intervallo 0..1,
/// calcolato con un istogramma da 2048 classi.
double percentile(Float32List values, double pct, {Float32List? weightMask}) {
  const bins = 2048;
  final hist = Int32List(bins);
  var count = 0;
  for (var i = 0; i < values.length; i++) {
    if (weightMask != null && weightMask[i] <= 0.5) continue;
    var v = values[i];
    if (v < 0) v = 0;
    if (v > 1) v = 1;
    hist[(v * (bins - 1)).round()]++;
    count++;
  }
  if (count == 0) return 0;
  final target = count * pct / 100.0;
  var acc = 0;
  for (var k = 0; k < bins; k++) {
    acc += hist[k];
    if (acc >= target) return k / (bins - 1);
  }
  return 1;
}

// ---------------------------------------------------------------------------
// Analisi automatica

Analysis analyze(Planes p) {
  final n = p.w * p.h;
  final lum = p.luminance();
  double sr = 0, sg = 0, sb = 0;
  var cnt = 0;
  for (var i = 0; i < n; i++) {
    final l = lum[i];
    if (l > 0.15 && l < 0.9) {
      sr += p.r[i];
      sg += p.g[i];
      sb += p.b[i];
      cnt++;
    }
  }
  if (cnt < 100) {
    sr = sg = sb = 0;
    for (var i = 0; i < n; i++) {
      sr += p.r[i];
      sg += p.g[i];
      sb += p.b[i];
    }
    cnt = n;
  }
  final mr = math.max(sr / cnt, 1e-3);
  final mg = math.max(sg / cnt, 1e-3);
  final mb = math.max(sb / cnt, 1e-3);
  final mean = (mr + mg + mb) / 3;
  double cl(double g) => g.clamp(0.7, 1.4).toDouble();
  final gr = cl(mean / mr), gg = cl(mean / mg), gb = cl(mean / mb);

  final lb = Float32List(n);
  for (var i = 0; i < n; i++) {
    lb[i] = (0.299 * p.r[i] * gr + 0.587 * p.g[i] * gg + 0.114 * p.b[i] * gb)
        .clamp(0.0, 1.0)
        .toDouble();
  }
  final lo = percentile(lb, 0.5);
  final hi = math.max(percentile(lb, 99.5), lo + 0.2);
  return Analysis(gainR: gr, gainG: gg, gainB: gb, black: lo, white: hi);
}

/// Maschera morbida del quadrante: 1 dentro, 0 fuori, bordo sfumato.
Float32List dialMask(int w, int h, Dial d, {double feather = 0.08}) {
  final m = Float32List(w * h);
  final rad = d.r * math.min(w, h);
  final cx = d.cx * w, cy = d.cy * h;
  for (var y = 0; y < h; y++) {
    final dy = y - cy;
    for (var x = 0; x < w; x++) {
      final dx = x - cx;
      final dist = math.sqrt(dx * dx + dy * dy) / rad;
      m[y * w + x] = ((1 - dist) / feather + 0.5).clamp(0.0, 1.0).toDouble();
    }
  }
  return m;
}

/// Velo del riflesso: il "pavimento" della luminosità (minimo locale a
/// bassa frequenza) sopra il livello scuro del quadrante. I dettagli
/// chiari (indici, lancette) non lo alzano, quindi non vengono spenti.
Float32List veilMap(Float32List lum, Float32List mask, int w, int h) {
  final f = math.max(1, math.max(w, h) ~/ 256);
  final sw = (w + f - 1) ~/ f, sh = (h + f - 1) ~/ f;
  final small = Float32List(sw * sh);
  final sm = Float32List(sw * sh);
  for (var y = 0; y < sh; y++) {
    for (var x = 0; x < sw; x++) {
      final src = (y * f) * w + x * f;
      small[y * sw + x] = lum[src];
      sm[y * sw + x] = mask[src];
    }
  }
  const rad = 6;
  final tmp = Float32List(sw * sh);
  for (var y = 0; y < sh; y++) {
    for (var x = 0; x < sw; x++) {
      var mn = 2.0;
      for (var k = -rad; k <= rad; k++) {
        final v = small[y * sw + (x + k).clamp(0, sw - 1)];
        if (v < mn) mn = v;
      }
      tmp[y * sw + x] = mn;
    }
  }
  final mn = Float32List(sw * sh);
  for (var y = 0; y < sh; y++) {
    for (var x = 0; x < sw; x++) {
      var m = 2.0;
      for (var k = -rad; k <= rad; k++) {
        final v = tmp[(y + k).clamp(0, sh - 1) * sw + x];
        if (v < m) m = v;
      }
      mn[y * sw + x] = m;
    }
  }
  final blurred = gaussBlur(mn, sw, sh, rad);
  var anyInside = false;
  for (var i = 0; i < sm.length; i++) {
    if (sm[i] > 0.5) {
      anyInside = true;
      break;
    }
  }
  final floor = percentile(blurred, 10, weightMask: anyInside ? sm : null);
  // ingrandimento bilineare alla misura piena
  final out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final fy = ((y + 0.5) / f - 0.5).clamp(0.0, sh - 1.0);
    final y0 = fy.floor(), y1 = math.min(y0 + 1, sh - 1);
    final ty = fy - y0;
    for (var x = 0; x < w; x++) {
      final fx = ((x + 0.5) / f - 0.5).clamp(0.0, sw - 1.0);
      final x0 = fx.floor(), x1 = math.min(x0 + 1, sw - 1);
      final tx = fx - x0;
      final a = blurred[y0 * sw + x0] * (1 - tx) + blurred[y0 * sw + x1] * tx;
      final b = blurred[y1 * sw + x0] * (1 - tx) + blurred[y1 * sw + x1] * tx;
      final v = a * (1 - ty) + b * ty - floor;
      out[y * w + x] = v < 0 ? 0 : (v > 1 ? 1 : v);
    }
  }
  return out;
}

/// Toglie i puntini di polvere nel quadrante. Un pixel è "polvere" se è più
/// chiaro (o più scuro) di TUTTI i punti di un anello attorno a lui:
/// i bordi di lancette, indici e scritte toccano l'anello, quindi restano.
/// Restituisce quanti pixel sono stati riconosciuti come polvere.
int removeDust(Planes p, Float32List mask, double strength, double scale) {
  final w = p.w, h = p.h;
  final lum = p.luminance();
  final rad = math.max(3, ((3 + 3 * strength) * scale).round());
  final t = 0.10 - 0.04 * strength;
  final offs = <List<int>>[];
  for (var k = 0; k < 16; k++) {
    final a = k * 2 * math.pi / 16;
    offs.add([(rad * math.cos(a)).round(), (rad * math.sin(a)).round()]);
  }
  final hit = Uint8List(w * h);
  var found = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (mask[i] <= 0.5) continue;
      var mx = -1.0, mn = 2.0;
      for (final o in offs) {
        final xx = (x + o[0]).clamp(0, w - 1);
        final yy = (y + o[1]).clamp(0, h - 1);
        final v = lum[yy * w + xx];
        if (v > mx) mx = v;
        if (v < mn) mn = v;
      }
      final l = lum[i];
      if (l > mx + t || l < mn - t) {
        hit[i] = 1;
        found++;
      }
    }
  }
  if (found == 0) return 0;
  // allarga di un pixel per prendere anche l'alone del puntino
  final grow = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (hit[y * w + x] == 0) continue;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx, yy = y + dy;
          if (xx >= 0 && yy >= 0 && xx < w && yy < h) grow[yy * w + xx] = 1;
        }
      }
    }
  }
  final r0 = Float32List.fromList(p.r);
  final g0 = Float32List.fromList(p.g);
  final b0 = Float32List.fromList(p.b);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (grow[i] == 0) continue;
      double sr = 0, sg = 0, sb = 0;
      for (final o in offs) {
        final j = (y + o[1]).clamp(0, h - 1) * w + (x + o[0]).clamp(0, w - 1);
        sr += r0[j];
        sg += g0[j];
        sb += b0[j];
      }
      p.r[i] = sr / offs.length;
      p.g[i] = sg / offs.length;
      p.b[i] = sb / offs.length;
    }
  }
  return found;
}

// ---------------------------------------------------------------------------
// Ritocco completo

/// Applica tutto il ritocco. Le dimensioni dei filtri sono pensate per una
/// foto con lato lungo di 2048 px e scalate sulla misura reale, così
/// l'anteprima piccola somiglia al risultato salvato.
Planes enhance(RgbImage src, Analysis an, EnhanceParams p) {
  final img = Planes.fromRgb(src);
  final w = img.w, h = img.h, n = w * h;
  final scale = math.max(w, h) / 2048.0;
  int s(double x) => math.max(1, (x * scale).round());

  // 1. bilanciamento del bianco, calore, livelli
  final a = p.autoColor ? an : Analysis.neutral;
  final gr = a.gainR * (1 + 0.08 * p.warmth);
  final gg = a.gainG;
  final gb = a.gainB * (1 - 0.08 * p.warmth);
  final span = a.white - a.black;
  for (var i = 0; i < n; i++) {
    final r = (img.r[i] * gr).clamp(0.0, 1.0).toDouble();
    final g = (img.g[i] * gg).clamp(0.0, 1.0).toDouble();
    final b = (img.b[i] * gb).clamp(0.0, 1.0).toDouble();
    final l0 = 0.299 * r + 0.587 * g + 0.114 * b;
    final ln = ((l0 - a.black) / span).clamp(0.0, 1.0);
    final k = ln / math.max(l0, 1e-3);
    img.r[i] = (r * k).clamp(0.0, 1.0).toDouble();
    img.g[i] = (g * k).clamp(0.0, 1.0).toDouble();
    img.b[i] = (b * k).clamp(0.0, 1.0).toDouble();
  }

  // 2. riduzione rumore (filtro guidato per canale)
  if (p.denoise > 0) {
    final eps = math.pow(0.02 + 0.08 * p.denoise, 2).toDouble();
    final rr = s(3);
    final nr = guidedSelf(img.r, w, h, rr, eps);
    final ng = guidedSelf(img.g, w, h, rr, eps);
    final nb = guidedSelf(img.b, w, h, rr, eps);
    // a forza bassa mescola con l'originale
    final k = math.min(1.0, p.denoise * 2);
    for (var i = 0; i < n; i++) {
      img.r[i] += (nr[i] - img.r[i]) * k;
      img.g[i] += (ng[i] - img.g[i]) * k;
      img.b[i] += (nb[i] - img.b[i]) * k;
    }
  }

  // 3. toni sulla luminosità
  final lum = img.luminance();
  final l2 = Float32List(n);
  final expo = math.pow(2, p.exposure).toDouble();
  final c = p.contrast;
  for (var i = 0; i < n; i++) {
    var v = lum[i] * expo;
    final sh = (1 - v / 0.5).clamp(0.0, 1.0);
    v += p.shadows * 0.5 * (1 - v) * sh * sh;
    final hl = ((v - 0.6) / 0.4).clamp(0.0, 1.0);
    v -= p.highlights * 0.35 * hl * hl * (v - 0.6);
    v = v.clamp(0.0, 1.0).toDouble();
    v -= c * math.sin(2 * math.pi * v) / (2 * math.pi);
    l2[i] = v;
  }

  // 4. quadrante: riflesso e chiarezza
  final mask = p.dialOn ? dialMask(w, h, p.dial) : Float32List(n);
  if (p.dialOn && (p.glare > 0 || p.detail > 0)) {
    if (p.glare > 0) {
      final veil = veilMap(l2, mask, w, h);
      for (var i = 0; i < n; i++) {
        final v = (p.glare * mask[i] * 0.9 * veil[i]).clamp(0.0, 0.6);
        l2[i] = (l2[i] - v) / (1 - v);
      }
    }
    if (p.detail > 0) {
      final base = guidedSelf(l2, w, h, s(16), 0.01);
      for (var i = 0; i < n; i++) {
        l2[i] += p.detail * mask[i] * (l2[i] - base[i]);
      }
    }
  }
  for (var i = 0; i < n; i++) {
    final l = lum[i];
    if (l <= 1e-3) continue;
    final k = l2[i].clamp(0.0, 1.2) / l;
    img.r[i] = (img.r[i] * k).clamp(0.0, 1.0).toDouble();
    img.g[i] = (img.g[i] * k).clamp(0.0, 1.0).toDouble();
    img.b[i] = (img.b[i] * k).clamp(0.0, 1.0).toDouble();
  }

  // 5. polvere
  if (p.dialOn && p.dust > 0) {
    removeDust(img, mask, p.dust, scale);
  }

  // 6. nitidezza (sulla luminosità, con soglia per non alzare il rumore)
  if (p.sharpen > 0 || (p.dialOn && p.detail > 0)) {
    final l = img.luminance();
    final bl = gaussBlur(l, w, h, s(1.5));
    for (var i = 0; i < n; i++) {
      final amt = p.sharpen * 1.5 + p.detail * mask[i] * 0.8;
      var hp = l[i] - bl[i];
      final mag = hp.abs() - 0.02;
      if (mag <= 0) continue;
      hp = hp.sign * mag * amt;
      img.r[i] += hp;
      img.g[i] += hp;
      img.b[i] += hp;
    }
  }

  // 7. sfondo chiaro e poco colorato -> bianco (mai dentro il quadrante)
  if (p.background > 0) {
    final thr = 0.82 - 0.25 * p.background;
    final k = math.sqrt(p.background);
    for (var i = 0; i < n; i++) {
      final r = img.r[i].clamp(0.0, 1.0).toDouble();
      final g = img.g[i].clamp(0.0, 1.0).toDouble();
      final b = img.b[i].clamp(0.0, 1.0).toDouble();
      final l = 0.299 * r + 0.587 * g + 0.114 * b;
      final sat = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
      final t = ((l - thr) / 0.12).clamp(0.0, 1.0) *
          (1 - sat / 0.18).clamp(0.0, 1.0) *
          (1 - mask[i]);
      final m = k * t;
      img.r[i] = r + m * (1 - r);
      img.g[i] = g + m * (1 - g);
      img.b[i] = b + m * (1 - b);
    }
  }

  if (p.square) return cropSquare(img, p.dialOn ? p.dial : const Dial());
  return img;
}

/// Ritaglio quadrato del lato corto, centrato sul quadrante quando possibile.
Planes cropSquare(Planes p, Dial d) {
  final side = math.min(p.w, p.h);
  final x0 = (d.cx * p.w - side / 2).round().clamp(0, p.w - side);
  final y0 = (d.cy * p.h - side / 2).round().clamp(0, p.h - side);
  final n = side * side;
  final r = Float32List(n), g = Float32List(n), b = Float32List(n);
  for (var y = 0; y < side; y++) {
    final src = (y + y0) * p.w + x0;
    final dst = y * side;
    r.setRange(dst, dst + side, p.r, src);
    g.setRange(dst, dst + side, p.g, src);
    b.setRange(dst, dst + side, p.b, src);
  }
  return Planes(side, side, r, g, b);
}
