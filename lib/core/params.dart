/// Impostazioni del ritocco. Tutti i valori sono numeri semplici, così
/// l'oggetto può passare a un isolate senza problemi.
class Dial {
  /// Centro, in frazione di larghezza/altezza dell'immagine (0..1).
  final double cx;
  final double cy;

  /// Raggio, in frazione del lato corto dell'immagine.
  final double r;

  const Dial({this.cx = 0.5, this.cy = 0.5, this.r = 0.3});

  Dial copyWith({double? cx, double? cy, double? r}) => Dial(
        cx: (cx ?? this.cx).clamp(0.0, 1.0),
        cy: (cy ?? this.cy).clamp(0.0, 1.0),
        r: (r ?? this.r).clamp(0.05, 0.75),
      );
}

/// Valori misurati sulla foto originale (bilanciamento e livelli automatici).
class Analysis {
  final double gainR, gainG, gainB;
  final double black, white;

  const Analysis({
    this.gainR = 1,
    this.gainG = 1,
    this.gainB = 1,
    this.black = 0,
    this.white = 1,
  });

  static const neutral = Analysis();
}

class EnhanceParams {
  // Generali
  final bool autoColor; // bilanciamento del bianco + livelli automatici
  final double exposure; // -1..1 (stop)
  final double contrast; // -1..1
  final double warmth; // -1..1
  final double shadows; // 0..1 schiarisce le ombre
  final double highlights; // 0..1 recupera le luci
  final double denoise; // 0..1
  final double sharpen; // 0..1

  // Quadrante
  final bool dialOn;
  final Dial dial;
  final double detail; // 0..1 chiarezza locale
  final double glare; // 0..1 riduce il velo di riflesso sul vetro
  final double dust; // 0..1 toglie puntini di polvere

  // Sfondo e ritaglio
  final double background; // 0..1 porta lo sfondo chiaro verso il bianco
  final bool square; // ritaglio 1:1 centrato sul quadrante

  const EnhanceParams({
    this.autoColor = true,
    this.exposure = 0,
    this.contrast = 0,
    this.warmth = 0,
    this.shadows = 0,
    this.highlights = 0,
    this.denoise = 0,
    this.sharpen = 0,
    this.dialOn = false,
    this.dial = const Dial(),
    this.detail = 0,
    this.glare = 0,
    this.dust = 0,
    this.background = 0,
    this.square = false,
  });

  /// Nessuna modifica (solo eventuale colore automatico spento).
  static const none = EnhanceParams(autoColor: false);

  /// Il "Migliora in un tocco": valori provati sul prototipo.
  static const auto = EnhanceParams(
    autoColor: true,
    warmth: 0.2,
    contrast: 0.15,
    shadows: 0.2,
    highlights: 0.3,
    denoise: 0.5,
    sharpen: 0.5,
    dialOn: true,
    detail: 0.5,
    glare: 0.6,
    dust: 0.6,
    background: 0.6,
  );

  EnhanceParams copyWith({
    bool? autoColor,
    double? exposure,
    double? contrast,
    double? warmth,
    double? shadows,
    double? highlights,
    double? denoise,
    double? sharpen,
    bool? dialOn,
    Dial? dial,
    double? detail,
    double? glare,
    double? dust,
    double? background,
    bool? square,
  }) =>
      EnhanceParams(
        autoColor: autoColor ?? this.autoColor,
        exposure: exposure ?? this.exposure,
        contrast: contrast ?? this.contrast,
        warmth: warmth ?? this.warmth,
        shadows: shadows ?? this.shadows,
        highlights: highlights ?? this.highlights,
        denoise: denoise ?? this.denoise,
        sharpen: sharpen ?? this.sharpen,
        dialOn: dialOn ?? this.dialOn,
        dial: dial ?? this.dial,
        detail: detail ?? this.detail,
        glare: glare ?? this.glare,
        dust: dust ?? this.dust,
        background: background ?? this.background,
        square: square ?? this.square,
      );

  /// Tiene il quadrante già posizionato quando si applica un preset.
  EnhanceParams withDial(Dial d) => copyWith(dial: d);
}
