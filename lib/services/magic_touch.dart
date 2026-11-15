import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/shape.dart';

/// "Tocca il quadrante": IA di Google (MediaPipe Interactive Segmenter,
/// modello MagicTouch). Il modello (~6 MB) si scarica una volta da Google e
/// poi lavora sul telefono, anche offline.
class MagicTouch {
  static const _channel = MethodChannel('dphotowatch/magictouch');
  static const modelUrl =
      'https://storage.googleapis.com/mediapipe-models/interactive_segmenter/'
      'magic_touch/float32/latest/magic_touch.tflite';

  static Future<File> _modelFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/magic_touch.tflite');
  }

  static Future<bool> isModelReady() async {
    final f = await _modelFile();
    return await f.exists() && await f.length() > 1000000;
  }

  /// Scarica il modello se non c'è già. [onProgress] riceve 0..1.
  static Future<File> ensureModel({void Function(double)? onProgress}) async {
    final f = await _modelFile();
    if (await f.exists() && await f.length() > 1000000) return f;
    final tmp = File('${f.path}.part');
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(modelUrl));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw Exception('download non riuscito (codice ${res.statusCode})');
      }
      final total = res.contentLength;
      var got = 0;
      final sink = tmp.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call(got / total);
      }
      await sink.close();
      if (await tmp.length() < 1000000) {
        throw Exception('file del modello incompleto');
      }
      await tmp.rename(f.path);
      return f;
    } finally {
      client.close(force: true);
    }
  }

  /// Trova il contorno dell'oggetto toccato in ([x], [y]) (0..1) nella foto
  /// [jpeg] (già raddrizzata). Restituisce null se il risultato non è
  /// credibile come quadrante.
  static Future<DialShape?> segment(Uint8List jpeg, double x, double y,
      {void Function(double)? onProgress}) async {
    if (!Platform.isAndroid) {
      throw Exception('disponibile solo su Android');
    }
    final model = await ensureModel(onProgress: onProgress);
    final dir = await getTemporaryDirectory();
    final img = File('${dir.path}/magictouch_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await img.writeAsBytes(jpeg, flush: true);
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('segment', {
        'model': model.path,
        'image': img.path,
        'x': x,
        'y': y,
      });
      if (res == null) return null;
      final w = res['width'] as int;
      final h = res['height'] as int;
      final masks = (res['masks'] as List).cast<Float32List>();
      return compute(_bestShape, _MaskSet(masks, w, h, x, y));
    } finally {
      unawaited(img.delete().then((_) {}, onError: (_) {}));
    }
  }
}

class _MaskSet {
  final List<Float32List> masks;
  final int w, h;
  final double x, y;
  _MaskSet(this.masks, this.w, this.h, this.x, this.y);
}

DialShape? _bestShape(_MaskSet s) => shapeFromConfidence(s.masks, s.w, s.h, s.x, s.y);

/// Sceglie la maschera che "contiene" il punto toccato, tiene solo la zona
/// collegata al punto e ne prende il contorno convesso.
DialShape? shapeFromConfidence(
    List<Float32List> masks, int w, int h, double x, double y) {
  if (masks.isEmpty || w <= 0 || h <= 0) return null;
  final px = (x * w).floor().clamp(0, w - 1);
  final py = (y * h).floor().clamp(0, h - 1);
  Float32List? best;
  var bestV = -1.0;
  for (final m in masks) {
    if (m.length != w * h) continue;
    final v = m[py * w + px];
    if (v > bestV) {
      bestV = v;
      best = m;
    }
  }
  if (best == null || bestV < 0.5) return null;
  final n = w * h;
  final bin = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (best[i] >= 0.5) bin[i] = 1;
  }
  // zona collegata al punto toccato
  final keep = Uint8List(n);
  final q = Int32List(n);
  var head = 0, tail = 0;
  final s0 = py * w + px;
  q[tail++] = s0;
  keep[s0] = 1;
  while (head < tail) {
    final i = q[head++];
    final cx = i % w, cy = i ~/ w;
    for (var d = 0; d < 4; d++) {
      var xx = cx, yy = cy;
      if (d == 0) xx++;
      if (d == 1) xx--;
      if (d == 2) yy++;
      if (d == 3) yy--;
      if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
      final j = yy * w + xx;
      if (bin[j] != 0 && keep[j] == 0) {
        keep[j] = 1;
        q[tail++] = j;
      }
    }
  }
  final area = tail / n;
  if (area < 0.005 || area > 0.8) return null;
  return shapeFromMask(keep, w, h);
}
