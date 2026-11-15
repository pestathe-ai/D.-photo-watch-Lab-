import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'dial_finder.dart';
import 'params.dart';
import 'pipeline.dart';
import 'shape.dart';

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
/// Maschera dell'orologio data dallo scontorno IA (0 sfondo .. 255 orologio).
class SubjectMask {
  final int width;
  final int height;
  final Uint8List data;

  SubjectMask(this.width, this.height, this.data);

  /// La stessa maschera alla misura di un'altra versione della foto.
  Uint8List forSize(int w, int h) => resizeMask(data, width, height, w, h);
}

class LoadedPhoto {
  final RgbImage full;
  final RgbImage preview;
  final Analysis analysis;

  /// Anteprima già raddrizzata, senza EXIF: è anche quella passata allo
  /// scontorno IA, così la maschera ha esattamente le sue misure.
  final Uint8List previewJpeg;
  final DialGuess dialGuess;

  /// Contorno del quadrante trovato da solo (qualsiasi forma), se c'è.
  final DialShape? dialShape;
  SubjectMask? subject;

  LoadedPhoto(this.full, this.preview, this.analysis, this.previewJpeg,
      this.dialGuess, this.dialShape, {this.subject});

  bool get dialFound => dialShape != null || dialGuess.found;
}

LoadedPhoto? loadPhoto(Uint8List bytes) {
  final full = decodeToRgb(bytes, kExportMaxSide);
  if (full == null) return null;
  final preview = shrink(full, kPreviewMaxSide);
  final analysis = analyze(Planes.fromRgb(preview));
  return LoadedPhoto(full, preview, analysis, encodeJpeg(preview, quality: 90),
      findDial(preview), findDialShape(preview));
}

/// Applica un preset con il quadrante trovato da solo: prima la forma
/// (rettangolare, tonneau, tonda), poi il cerchio; se non trova niente il
/// ritocco del quadrante resta spento.
EnhanceParams presetFor(EnhanceParams preset, DialGuess g, DialShape? shape) {
  if (shape != null) return preset.copyWith(shape: shape);
  if (g.found) return preset.withDial(g.dial);
  return preset.copyWith(dialOn: false, clearShape: true);
}

EnhanceParams autoParamsFor(DialGuess g, [DialShape? shape]) =>
    presetFor(EnhanceParams.auto, g, shape);

/// Per la modalità a più foto: analisi, quadrante e anteprima raddrizzata
/// (per lo scontorno), senza tenere in memoria la foto grande.
class BatchPrepared {
  final Analysis analysis;
  final DialGuess dialGuess;
  final DialShape? dialShape;
  final EnhanceParams params;
  final Uint8List previewJpeg;
  final int previewW;
  final int previewH;

  BatchPrepared(this.analysis, this.dialGuess, this.dialShape, this.params,
      this.previewJpeg, this.previewW, this.previewH);

  bool get dialFound => dialShape != null || dialGuess.found;
}

BatchPrepared? prepareBatchItem(Uint8List bytes) {
  final preview = decodeToRgb(bytes, kPreviewMaxSide);
  if (preview == null) return null;
  final analysis = analyze(Planes.fromRgb(preview));
  final guess = findDial(preview);
  final shape = findDialShape(preview);
  return BatchPrepared(analysis, guess, shape, autoParamsFor(guess, shape),
      encodeJpeg(preview, quality: 90), preview.width, preview.height);
}

/// Ritocca una foto partendo dal file originale, alla misura [maxSide]
/// (anteprima della serie o salvataggio).
class FileRenderJob {
  final Uint8List bytes;
  final int maxSide;
  final Analysis analysis;
  final EnhanceParams params;
  final SubjectMask? subject;
  final int quality;

  FileRenderJob(this.bytes, this.maxSide, this.analysis, this.params,
      {this.subject, this.quality = 93});
}

Uint8List? runFileRenderJob(FileRenderJob j) {
  final im = decodeToRgb(j.bytes, j.maxSide);
  if (im == null) return null;
  return renderJpeg(im, j.analysis, j.params,
      subject: j.subject, quality: j.quality);
}

/// Ritocca e codifica in JPG (usato sia per l'anteprima sia per il salvataggio).
Uint8List renderJpeg(RgbImage src, Analysis an, EnhanceParams p,
    {SubjectMask? subject, int quality = 92}) {
  final m = subject?.forSize(src.width, src.height);
  return encodeJpeg(enhance(src, an, p, subject: m).toRgb(), quality: quality);
}
