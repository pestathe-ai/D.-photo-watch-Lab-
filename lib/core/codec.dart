import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'dial_finder.dart';
import 'params.dart';
import 'pipeline.dart';

/// Lato lungo massimo della foto salvata. Oltre questa misura i siti di
/// annunci rimpiccioliscono comunque, e la memoria del telefono ringrazia.
const int kExportMaxSide = 2400;

/// Lato lungo dell'anteprima mostrata mentre si regolano i cursori.
const int kPreviewMaxSide = 1000;

/// Decodifica JPG/PNG/HEIC già convertito, raddrizza secondo l'EXIF e
/// rimpicciolisce a [maxSide]. Restituisce null se il file non è leggibile.
RgbImage? decodeToRgb(Uint8List bytes, int maxSide) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var im = img.bakeOrientation(decoded);
  final long = math.max(im.width, im.height);
  if (long > maxSide) {
    final k = maxSide / long;
    im = img.copyResize(
      im,
      width: math.max(1, (im.width * k).round()),
      height: math.max(1, (im.height * k).round()),
      interpolation: img.Interpolation.average,
    );
  }
  if (im.format != img.Format.uint8 || im.numChannels != 3 || im.hasPalette) {
    im = im.convert(format: img.Format.uint8, numChannels: 3);
  }
  final rgb = Uint8List.fromList(im.getBytes(order: img.ChannelOrder.rgb));
  return RgbImage(im.width, im.height, rgb);
}

/// Rimpicciolisce una foto già decodificata (per l'anteprima).
RgbImage shrink(RgbImage src, int maxSide) {
  final long = math.max(src.width, src.height);
  if (long <= maxSide) return src;
  final k = maxSide / long;
  final im = img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: Uint8List.fromList(src.rgb).buffer,
    numChannels: 3,
  );
  final out = img.copyResize(
    im,
    width: math.max(1, (src.width * k).round()),
    height: math.max(1, (src.height * k).round()),
    interpolation: img.Interpolation.average,
  );
  return RgbImage(out.width, out.height,
      Uint8List.fromList(out.getBytes(order: img.ChannelOrder.rgb)));
}

Uint8List encodeJpeg(RgbImage im, {int quality = 92}) {
  final out = img.Image.fromBytes(
    width: im.width,
    height: im.height,
    bytes: Uint8List.fromList(im.rgb).buffer,
    numChannels: 3,
  );
  return img.encodeJpg(out, quality: quality);
}

/// Tutto quello che serve dopo aver scelto una foto: originale per
/// l'esportazione, anteprima piccola e analisi automatica.
class LoadedPhoto {
  final RgbImage full;
  final RgbImage preview;
  final Analysis analysis;
  final Uint8List previewJpeg;
  final DialGuess dialGuess;

  LoadedPhoto(this.full, this.preview, this.analysis, this.previewJpeg,
      this.dialGuess);
}

LoadedPhoto? loadPhoto(Uint8List bytes) {
  final full = decodeToRgb(bytes, kExportMaxSide);
  if (full == null) return null;
  final preview = shrink(full, kPreviewMaxSide);
  final analysis = analyze(Planes.fromRgb(preview));
  return LoadedPhoto(full, preview, analysis, encodeJpeg(preview, quality: 90),
      findDial(preview));
}

/// Parametri "Migliora in un tocco" per una foto, con il quadrante trovato
/// da solo (se non lo trova, il ritocco del quadrante resta spento).
EnhanceParams autoParamsFor(DialGuess g) => g.found
    ? EnhanceParams.auto.withDial(g.dial)
    : EnhanceParams.auto.copyWith(dialOn: false);

/// Per la modalità a più foto: analisi, quadrante e anteprima già migliorata,
/// senza tenere in memoria la foto grande.
class BatchPrepared {
  final Analysis analysis;
  final DialGuess dialGuess;
  final EnhanceParams params;
  final Uint8List thumbJpeg;

  BatchPrepared(this.analysis, this.dialGuess, this.params, this.thumbJpeg);
}

BatchPrepared? prepareBatchItem(Uint8List bytes) {
  final preview = decodeToRgb(bytes, kPreviewMaxSide);
  if (preview == null) return null;
  final analysis = analyze(Planes.fromRgb(preview));
  final guess = findDial(preview);
  final params = autoParamsFor(guess);
  final thumb = renderJpeg(preview, analysis, params.copyWith(square: false),
      quality: 85);
  return BatchPrepared(analysis, guess, params, thumb);
}

/// Esporta una foto della serie alla misura piena.
class ExportJob {
  final Uint8List bytes;
  final Analysis analysis;
  final EnhanceParams params;

  ExportJob(this.bytes, this.analysis, this.params);
}

Uint8List? runExportJob(ExportJob j) {
  final full = decodeToRgb(j.bytes, kExportMaxSide);
  if (full == null) return null;
  return renderJpeg(full, j.analysis, j.params, quality: 93);
}

/// Ritocca e codifica in JPG (usato sia per l'anteprima sia per il salvataggio).
Uint8List renderJpeg(RgbImage src, Analysis an, EnhanceParams p,
    {int quality = 92}) {
  return encodeJpeg(enhance(src, an, p).toRgb(), quality: quality);
}
