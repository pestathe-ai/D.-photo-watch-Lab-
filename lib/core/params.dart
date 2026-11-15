import 'shape.dart';

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

  // Stile "ricco" (ricavato dalle foto ritoccate dell'utente)
  final double look; // 0..1 curva dei toni profonda
  final double clarity; // 0..1 chiarezza fuori dal quadrante (cinturino, cassa)
  final double vibrance; // 0..1 colori già saturi più ricchi

  // Quadrante
  final bool dialOn;
  final Dial dial; // cerchio, usato se [shape] è null
  final DialShape? shape; // contorno di qualsiasi forma
  final double detail; // 0..1 chiarezza locale
  final double glare; // 0..1 riduce il velo di riflesso sul vetro
  final double dust; // 0..1 toglie puntini di polvere
  final double smooth; // 0..1 ammorbidisce micro-segni e graffietti

  // Sfondo e ritaglio
  final double bgClean; // 0..1 sfondo scuro più pulito (rumore e pelucchi)
  final double background; // 0..1 porta lo sfondo verso il bianco
  final bool square; // ritaglio 1:1 centrato sul quadrante

  /// 0..1: quanto applicare gli effetti (il colore automatico resta pieno).
  final double intensity;

  const EnhanceParams({
    this.autoColor = true,
    this.exposure = 0,
    this.contrast = 0,
    this.warmth = 0,
    this.shadows = 0,
    this.highlights = 0,
    this.denoise = 0,
    this.sharpen = 0,
    this.look = 0,
    this.clarity = 0,
    this.vibrance = 0,
    this.dialOn = false,
    this.dial = const Dial(),
    this.shape,
    this.detail = 0,
    this.glare = 0,
    this.dust = 0,
    this.smooth = 0,
    this.bgClean = 0,
    this.background = 0,
    this.square = false,
    this.intensity = 1,
  });

  /// Nessuna modifica.
  static const none = EnhanceParams(autoColor: false);

  /// Stile "ricco": toni profondi, cinturino ricco, sfondo scuro pulito,
  /// nitidezza solo sui bordi veri. Tarato sulle coppie prima/dopo
  /// dell'utente; non inventa dettagli.
  static const rich = EnhanceParams(
    autoColor: false,
    look: 1,
    clarity: 0.5,
    vibrance: 0.5,
    denoise: 0.25,
    sharpen: 0.5,
    dialOn: true,
    glare: 0.25,
    dust: 0.5,
    smooth: 0.35,
    bgClean: 0.8,
  );

  /// Stile "naturale" (v0.3): luce e colore corretti con delicatezza.
  static const natural = EnhanceParams(
    autoColor: true,
    warmth: 0.1,
    contrast: 0.05,
    shadows: 0.15,
    highlights: 0.25,
    denoise: 0.4,
    sharpen: 0.2,
    dialOn: true,
    glare: 0.35,
    dust: 0.5,
    smooth: 0.5,
    bgClean: 0.4,
    intensity: 0.8,
  );

  /// "Migliora in un tocco".
  static const auto = rich;

  EnhanceParams copyWith({
    bool? autoColor,
    double? exposure,
    double? contrast,
    double? warmth,
    double? shadows,
    double? highlights,
    double? denoise,
    double? sharpen,
    double? look,
    double? clarity,
    double? vibrance,
    bool? dialOn,
    Dial? dial,
    DialShape? shape,
    bool clearShape = false,
    double? detail,
    double? glare,
    double? dust,
    double? smooth,
    double? bgClean,
    double? background,
    bool? square,
    double? intensity,
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
        look: look ?? this.look,
        clarity: clarity ?? this.clarity,
        vibrance: vibrance ?? this.vibrance,
        dialOn: dialOn ?? this.dialOn,
        dial: dial ?? this.dial,
        shape: clearShape ? null : (shape ?? this.shape),
        detail: detail ?? this.detail,
        glare: glare ?? this.glare,
        dust: dust ?? this.dust,
        smooth: smooth ?? this.smooth,
        bgClean: bgClean ?? this.bgClean,
        background: background ?? this.background,
        square: square ?? this.square,
        intensity: intensity ?? this.intensity,
      );

  /// Applica un preset tenendo il quadrante già trovato o posizionato.
  EnhanceParams keepDialOf(EnhanceParams other) => copyWith(
        dial: other.dial,
        shape: other.shape,
        clearShape: other.shape == null,
        dialOn: dialOn && (other.dialOn || other.shape != null),
      );

  /// Tiene il quadrante già posizionato quando si applica un preset.
  EnhanceParams withDial(Dial d) => copyWith(dial: d, clearShape: true);

  /// Regolazioni effettive: tutti gli effetti moltiplicati per l'intensità
  /// (colore automatico, calore, quadrante e ritaglio restano come sono).
  EnhanceParams effective() {
    final k = intensity.clamp(0.0, 1.0).toDouble();
    if (k == 1) return this;
    return copyWith(
      exposure: exposure * k,
      contrast: contrast * k,
      shadows: shadows * k,
      highlights: highlights * k,
      denoise: denoise * k,
      sharpen: sharpen * k,
      look: look * k,
      clarity: clarity * k,
      vibrance: vibrance * k,
      detail: detail * k,
      glare: glare * k,
      dust: dust * k,
      smooth: smooth * k,
      bgClean: bgClean * k,
      background: background * k,
      intensity: 1,
    );
  }
}
