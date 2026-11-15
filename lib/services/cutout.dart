import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/codec.dart';
import '../core/pipeline.dart';

/// Scontorno dell'orologio con l'IA di Google (ML Kit), sul telefono.
/// Il modello arriva da Google Play: la prima volta può servire internet,
/// poi funziona offline. Se non è disponibile, l'app usa il metodo semplice.
class Cutout {
  static SubjectSegmenter? _seg;

  /// Ultimo motivo per cui lo scontorno non ha funzionato (per l'interfaccia).
  static String? lastError;

  static Future<SubjectMask?> maskFor(
      Uint8List orientedJpeg, int width, int height) async {
    if (!Platform.isAndroid) return null;
    File? tmp;
    try {
      _seg ??= SubjectSegmenter(
        options: SubjectSegmenterOptions(
          enableForegroundBitmap: false,
          enableForegroundConfidenceMask: true,
          enableMultipleSubjects: SubjectResultOptions(
            enableConfidenceMask: false,
            enableSubjectBitmap: false,
          ),
        ),
      );
      final dir = await getTemporaryDirectory();
      tmp = File('${dir.path}/cutout_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await tmp.writeAsBytes(orientedJpeg, flush: true);
      final res = await _seg!.processImage(InputImage.fromFilePath(tmp.path));
      final conf = res.foregroundConfidenceMask;
      if (conf == null || conf.length != width * height) {
        lastError = 'maschera assente o di misura diversa';
        return null;
      }
      final mask = await compute(_toMask, _MaskJob(conf, width, height));
      if (mask == null) {
        lastError = 'orologio non riconosciuto';
        return null;
      }
      lastError = null;
      return SubjectMask(width, height, mask);
    } catch (e) {
      var msg = e is PlatformException ? (e.message ?? e.code) : '$e';
      msg = msg.split('\n').first;
      if (msg.length > 120) msg = '${msg.substring(0, 120)}…';
      lastError = msg.toLowerCase().contains('download') ||
              msg.toLowerCase().contains('waiting')
          ? 'il modello IA di Google si sta ancora scaricando, riprova tra poco'
          : msg;
      return null;
    } finally {
      if (tmp != null) unawaited(tmp.delete().then((_) {}, onError: (_) {}));
    }
  }
}

class _MaskJob {
  final List<double> conf;
  final int w, h;
  _MaskJob(this.conf, this.w, this.h);
}

/// Scarta maschere poco credibili (quasi vuote o quasi piene).
Uint8List? _toMask(_MaskJob j) {
  final m = confidenceToMask(j.conf, j.w, j.h);
  var fg = 0;
  for (final v in m) {
    if (v > 127) fg++;
  }
  final frac = fg / m.length;
  if (frac < 0.02 || frac > 0.95) return null;
  return m;
}
