import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;

import '../core/codec.dart';
import '../core/params.dart';
import '../core/pipeline.dart';
import '../core/shape.dart';
import '../services/cutout.dart';
import '../services/magic_touch.dart';
import 'theme.dart';

/// Lavoro da mandare a un isolate: solo dati semplici.
class RenderJob {
  final RgbImage src;
  final Analysis analysis;
  final EnhanceParams params;
  final int quality;
  final SubjectMask? subject;

  RenderJob(this.src, this.analysis, this.params, this.quality, {this.subject});
}

Uint8List runRenderJob(RenderJob j) => renderJpeg(j.src, j.analysis, j.params,
    subject: j.subject, quality: j.quality);

enum _Tab { auto, light, dial, background }

class EditorScreen extends StatefulWidget {
  final LoadedPhoto photo;

  /// Regolazioni di partenza (dalla serie di foto); se null usa
  /// "Migliora in un tocco" con il quadrante trovato da solo.
  final EnhanceParams? initial;

  /// Nella serie: al posto di Salva/Condividi c'è "Fatto", che torna
  /// indietro con le regolazioni.
  final bool batchMode;

  const EditorScreen({
    super.key,
    required this.photo,
    this.initial,
    this.batchMode = false,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late EnhanceParams _p;
  Uint8List? _shown;
  bool _rendering = false;
  bool _pending = false;
  bool _showOriginal = false;
  bool _exporting = false;
  _Tab _tab = _Tab.auto;
  Timer? _debounce;

  // gesto sul contorno del quadrante
  Dial? _dialAtStart;
  DialShape? _shapeAtStart;
  Offset _focalAtStart = Offset.zero;

  // "tocca il quadrante" con l'IA di Google
  bool _tapMode = false;
  String? _aiStatus;

  @override
  void initState() {
    super.initState();
    _p = widget.initial ??
        autoParamsFor(widget.photo.dialGuess, widget.photo.dialShape);
    // se il quadrante non è stato trovato, il cerchio parte dal centro
    if (!widget.photo.dialFound && widget.initial == null) {
      _p = _p.copyWith(dial: const Dial(r: 0.32));
    }
    _render();
    _cutout();
  }

  /// Stato dello scontorno IA per l'interfaccia.
  String _cutoutState = 'cerco l\'orologio…';

  Future<void> _cutout() async {
    final ph = widget.photo;
    if (ph.subject != null) {
      _cutoutState = 'attivo';
      return;
    }
    final m = await Cutout.maskFor(
        ph.previewJpeg, ph.preview.width, ph.preview.height);
    if (!mounted) return;
    setState(() {
      ph.subject = m;
      _cutoutState = m != null
          ? 'attivo'
          : 'non disponibile (${Cutout.lastError ?? 'motivo sconosciuto'}): uso il metodo semplice';
    });
    if (m != null) _render();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _update(EnhanceParams p, {bool now = false}) {
    setState(() => _p = p);
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: now ? 0 : 140), _render);
  }

  Future<void> _render() async {
    if (_rendering) {
      _pending = true;
      return;
    }
    _rendering = true;
    if (mounted) setState(() {});
    try {
      // l'anteprima non ritaglia: il quadrato si vede come cornice
      final job = RenderJob(widget.photo.preview, widget.photo.analysis,
          _p.copyWith(square: false), 88,
          subject: widget.photo.subject);
      final bytes = await compute(runRenderJob, job);
      if (!mounted) return;
      setState(() => _shown = bytes);
    } catch (e) {
      if (mounted) _snack('Errore nell\'anteprima: $e');
    } finally {
      _rendering = false;
      if (mounted) setState(() {});
      if (_pending) {
        _pending = false;
        _render();
      }
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// Cerchio che contiene grosso modo il contorno (per "Usa cerchio").
  Dial _circleAround(DialShape sh) {
    final c = sh.centroid;
    final pv = widget.photo.preview;
    final mn = math.min(pv.width, pv.height);
    double r = 0;
    for (var i = 0; i < sh.length; i++) {
      final dx = (sh.pts[2 * i] - c.x) * pv.width;
      final dy = (sh.pts[2 * i + 1] - c.y) * pv.height;
      r = math.max(r, math.sqrt(dx * dx + dy * dy));
    }
    return Dial(cx: c.x, cy: c.y, r: (0.9 * r / mn).clamp(0.05, 0.75));
  }

  void _redetect() {
    final ph = widget.photo;
    final next = presetFor(_p, ph.dialGuess, ph.dialShape).copyWith(dialOn: true);
    _update(ph.dialFound ? next : next.copyWith(dial: const Dial(r: 0.32)),
        now: true);
    setState(() => _aiStatus = ph.dialFound
        ? null
        : 'Non lo trovo da solo: prova "Tocca il quadrante (IA)".');
  }

  Future<void> _magicTouch(double x, double y) async {
    setState(() {
      _tapMode = false;
      _aiStatus = 'IA di Google al lavoro…';
    });
    try {
      final ready = await MagicTouch.isModelReady();
      if (!ready && mounted) {
        setState(() => _aiStatus = 'Scarico l\'IA di Google (una volta sola, ~6 MB)…');
      }
      final shape = await MagicTouch.segment(widget.photo.previewJpeg, x, y,
          onProgress: (v) {
        if (mounted) {
          setState(() => _aiStatus =
              'Scarico l\'IA di Google (una volta sola): ${(v * 100).round()}%');
        }
      });
      if (!mounted) return;
      if (shape == null) {
        setState(() => _aiStatus =
            'L\'IA non ha trovato un contorno credibile: tocca più al centro del quadrante.');
        return;
      }
      setState(() => _aiStatus = 'Quadrante trovato dall\'IA di Google.');
      _update(_p.copyWith(shape: shape, dialOn: true), now: true);
    } catch (e) {
      var msg = e is PlatformException ? (e.message ?? e.code) : '$e';
      msg = msg.split('\n').first;
      if (msg.length > 140) msg = '${msg.substring(0, 140)}…';
      if (mounted) setState(() => _aiStatus = 'IA non disponibile: $msg');
    }
  }

  Future<File?> _exportFile() async {
    setState(() => _exporting = true);
    try {
      final job = RenderJob(widget.photo.full, widget.photo.analysis, _p, 93,
          subject: widget.photo.subject);
      final bytes = await compute(runRenderJob, job);
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final f = File('${dir.path}/dphotowatch_$stamp.jpg');
      await f.writeAsBytes(bytes, flush: true);
      return f;
    } catch (e) {
      if (mounted) _snack('Errore nel salvataggio: $e');
      return null;
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _save() async {
    final f = await _exportFile();
    if (f == null) return;
    try {
      if (!await Gal.hasPermission(toAlbum: true)) {
        await Gal.requestPermission(toAlbum: true);
      }
      await Gal.putImage(f.path, album: 'D. Photo Watch Lab');
      if (mounted) _snack('Salvata in galleria (album "D. Photo Watch Lab")');
    } catch (e) {
      if (mounted) _snack('Non riesco a salvare in galleria: $e');
    }
  }

  Future<void> _share() async {
    final f = await _exportFile();
    if (f == null) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildEditorTheme(),
      child: Builder(builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Ritocco'),
            actions: widget.batchMode
                ? [
                    Padding(
                      padding: const EdgeInsets.only(right: Space.s),
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(_p),
                        icon: const Icon(Icons.check),
                        label: const Text('Fatto'),
                      ),
                    ),
                  ]
                : [
                    IconButton(
                      tooltip: 'Condividi',
                      onPressed: _exporting ? null : _share,
                      icon: const Icon(Icons.share_outlined),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: Space.s),
                      child: FilledButton.icon(
                        onPressed: _exporting ? null : _save,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Salva'),
                      ),
                    ),
                  ],
          ),
          body: SafeArea(
            bottom: false,
            child: LayoutBuilder(builder: (ctx2, c) {
              // il pannello si adatta all'altezza (e al testo grande)
              final panelH = (c.maxHeight * 0.4).clamp(200.0, 360.0);
              return Column(children: [
                Expanded(child: _previewArea(ctx)),
                if (_exporting) const LinearProgressIndicator(minHeight: 2),
                Material(
                  color: cs.surface,
                  child: SizedBox(height: panelH, child: _controls(ctx)),
                ),
              ]);
            }),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab.index,
            onDestinationSelected: (i) => setState(() {
              _tab = _Tab.values[i];
              if (_tab != _Tab.dial) _tapMode = false;
            }),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome),
                label: 'Auto',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune),
                label: 'Luce',
              ),
              NavigationDestination(
                icon: Icon(Icons.watch_outlined),
                selectedIcon: Icon(Icons.watch),
                label: 'Quadrante',
              ),
              NavigationDestination(
                icon: Icon(Icons.wallpaper_outlined),
                selectedIcon: Icon(Icons.wallpaper),
                label: 'Sfondo',
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _previewArea(BuildContext ctx) {
    final pv = widget.photo.preview;
    final cs = Theme.of(ctx).colorScheme;
    final t = Theme.of(ctx).textTheme;
    final hint = _tapMode
        ? 'Tocca il centro del quadrante'
        : _tab == _Tab.dial && _p.dialOn
            ? 'Trascina il contorno per spostarlo, pizzica per ridimensionarlo'
            : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s, Space.xs, Space.s, Space.s),
      child: Stack(children: [
        Positioned.fill(
          child: Center(
            child: AspectRatio(
              aspectRatio: pv.width / pv.height,
              child: LayoutBuilder(builder: (context, box) {
                final size = box.biggest;
                return GestureDetector(
                  onLongPressStart: (_) => setState(() => _showOriginal = true),
                  onLongPressEnd: (_) => setState(() => _showOriginal = false),
                  onTapUp: (d) {
                    if (!_tapMode) return;
                    _magicTouch(d.localPosition.dx / size.width,
                        d.localPosition.dy / size.height);
                  },
                  onScaleStart: (d) {
                    if (_tab != _Tab.dial || !_p.dialOn || _tapMode) return;
                    _dialAtStart = _p.dial;
                    _shapeAtStart = _p.shape;
                    _focalAtStart = d.localFocalPoint;
                  },
                  onScaleUpdate: (d) {
                    final start = _dialAtStart;
                    if (start == null) return;
                    final delta = d.localFocalPoint - _focalAtStart;
                    final dx = delta.dx / size.width, dy = delta.dy / size.height;
                    final sh = _shapeAtStart;
                    if (sh != null) {
                      _update(_p.copyWith(shape: sh.transformed(dx, dy, d.scale)));
                    } else {
                      _update(_p.copyWith(
                        dial: start.copyWith(
                          cx: start.cx + dx,
                          cy: start.cy + dy,
                          r: start.r * d.scale,
                        ),
                      ));
                    }
                  },
                  onScaleEnd: (_) {
                    _dialAtStart = null;
                    _shapeAtStart = null;
                  },
                  child: Semantics(
                    image: true,
                    label: _showOriginal ? 'Foto originale' : 'Anteprima della foto ritoccata',
                    child: Stack(fit: StackFit.expand, children: [
                      Image.memory(
                        _showOriginal || _shown == null
                            ? widget.photo.previewJpeg
                            : _shown!,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                      ),
                      if (!_showOriginal)
                        CustomPaint(
                          painter: _OverlayPainter(
                            dial: _p.dial,
                            shape: _p.shape,
                            showDial: _p.dialOn && _tab == _Tab.dial,
                            square: _p.square,
                            imgW: pv.width,
                            imgH: pv.height,
                            color: cs.secondary,
                          ),
                        ),
                    ]),
                  ),
                );
              }),
            ),
          ),
        ),
        // confronto prima/dopo: pulsante visibile (oltre alla pressione lunga)
        Positioned(
          left: Space.s,
          bottom: Space.s,
          child: _HoldButton(
            label: _showOriginal ? 'Originale' : 'Prima',
            onHold: (v) => setState(() => _showOriginal = v),
          ),
        ),
        Positioned(
          right: Space.m,
          top: Space.m,
          child: AnimatedOpacity(
            opacity: _rendering ? 1 : 0,
            duration: Motion.fast,
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        if (hint != null)
          Positioned(
            left: Space.xl * 4,
            right: Space.s,
            bottom: Space.s,
            child: Align(
              alignment: Alignment.bottomRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(hint,
                    style: t.bodySmall?.copyWith(color: Colors.white),
                    textAlign: TextAlign.right),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _section(BuildContext ctx, String title) {
    final t = Theme.of(ctx).textTheme;
    final cs = Theme.of(ctx).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xs),
      child: Semantics(
        header: true,
        child: Text(title,
            style: t.labelLarge?.copyWith(
                color: cs.onSurfaceVariant, letterSpacing: 0.4)),
      ),
    );
  }

  Widget _help(BuildContext ctx, String text) {
    final t = Theme.of(ctx).textTheme;
    final cs = Theme.of(ctx).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.s),
      child: Text(text, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
    );
  }

  Widget _controls(BuildContext ctx) {
    const pad = EdgeInsets.only(bottom: Space.l);
    switch (_tab) {
      case _Tab.auto:
        return ListView(padding: pad, children: [
          _section(ctx, 'Stile'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () =>
                      _update(EnhanceParams.rich.keepDialOf(_p), now: true),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Ricco'),
                ),
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () =>
                      _update(EnhanceParams.natural.keepDialOf(_p), now: true),
                  icon: const Icon(Icons.wb_sunny_outlined),
                  label: const Text('Naturale'),
                ),
              ),
            ]),
          ),
          _help(ctx, 'Ricco: toni profondi, cinturino vivo, sfondo scuro pulito. '
              'Naturale: più chiaro e delicato.'),
          _slider(ctx, 'Intensità', _p.intensity, 0, 1,
              (v) => _p.copyWith(intensity: v),
              reset: 1),
          SwitchListTile(
            title: const Text('Colore e livelli automatici'),
            subtitle: const Text('Toglie la dominante gialla o blu'),
            value: _p.autoColor,
            onChanged: (v) => _update(_p.copyWith(autoColor: v), now: true),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    _update(EnhanceParams.none.keepDialOf(_p), now: true),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Nessun ritocco'),
              ),
            ),
          ),
        ]);
      case _Tab.light:
        return ListView(padding: pad, children: [
          _help(ctx, 'Doppio tocco sul nome di un cursore per azzerarlo.'),
          _section(ctx, 'Stile'),
          _slider(ctx, 'Tono ricco', _p.look, 0, 1, (v) => _p.copyWith(look: v)),
          _slider(ctx, 'Chiarezza', _p.clarity, 0, 1,
              (v) => _p.copyWith(clarity: v)),
          _slider(ctx, 'Vivacità', _p.vibrance, 0, 1,
              (v) => _p.copyWith(vibrance: v)),
          _section(ctx, 'Luce'),
          _slider(ctx, 'Esposizione', _p.exposure, -1, 1,
              (v) => _p.copyWith(exposure: v)),
          _slider(ctx, 'Contrasto', _p.contrast, -1, 1,
              (v) => _p.copyWith(contrast: v)),
          _slider(ctx, 'Calore', _p.warmth, -1, 1, (v) => _p.copyWith(warmth: v)),
          _slider(ctx, 'Schiarisci ombre', _p.shadows, 0, 1,
              (v) => _p.copyWith(shadows: v)),
          _slider(ctx, 'Recupera luci', _p.highlights, 0, 1,
              (v) => _p.copyWith(highlights: v)),
          _section(ctx, 'Qualità'),
          _slider(ctx, 'Riduci rumore', _p.denoise, 0, 1,
              (v) => _p.copyWith(denoise: v)),
          _slider(ctx, 'Nitidezza', _p.sharpen, 0, 1,
              (v) => _p.copyWith(sharpen: v)),
        ]);
      case _Tab.dial:
        return ListView(padding: pad, children: [
          SwitchListTile(
            title: const Text('Ritocca il quadrante'),
            subtitle: Text(_p.shape != null
                ? 'Contorno trovato (forma libera)'
                : 'Contorno a cerchio'),
            value: _p.dialOn,
            onChanged: (v) => _update(_p.copyWith(dialOn: v), now: true),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: Wrap(spacing: Space.s, runSpacing: Space.s, children: [
              FilledButton.tonalIcon(
                onPressed: _p.dialOn
                    ? () => setState(() {
                          _tapMode = !_tapMode;
                          _aiStatus = _tapMode ? null : _aiStatus;
                        })
                    : null,
                icon: Icon(_tapMode ? Icons.close : Icons.touch_app_outlined),
                label: Text(_tapMode ? 'Annulla' : 'Tocca il quadrante (IA)'),
              ),
              OutlinedButton(
                onPressed: _p.dialOn ? _redetect : null,
                child: const Text('Trova di nuovo'),
              ),
              if (_p.shape != null)
                OutlinedButton(
                  onPressed: () => _update(
                      _p.copyWith(
                          clearShape: true,
                          dial: _circleAround(_p.shape!)),
                      now: true),
                  child: const Text('Usa cerchio'),
                ),
            ]),
          ),
          if (_aiStatus != null)
            Semantics(liveRegion: true, child: _help(ctx, _aiStatus!)),
          _section(ctx, 'Migliora'),
          _slider(ctx, 'Scritte e indici', _p.detail, 0, 1,
              (v) => _p.copyWith(detail: v),
              enabled: _p.dialOn),
          _slider(ctx, 'Anti-riflesso forte', _p.deglare, 0, 1,
              (v) => _p.copyWith(deglare: v),
              enabled: _p.dialOn),
          _help(ctx, 'Per quadranti scuri velati da cielo o finestra; sui '
              'quadranti chiari lascialo a zero.'),
          _slider(ctx, 'Anti-riflesso leggero', _p.glare, 0, 1,
              (v) => _p.copyWith(glare: v),
              enabled: _p.dialOn),
          _section(ctx, 'Pulizia, con cautela'),
          _slider(ctx, 'Togli polvere', _p.dust, 0, 1, (v) => _p.copyWith(dust: v),
              enabled: _p.dialOn),
          _slider(ctx, 'Ammorbidisci segni', _p.smooth, 0, 1,
              (v) => _p.copyWith(smooth: v),
              enabled: _p.dialOn),
          _help(ctx, 'Possono cancellare puntini stampati, tacche fini e '
              'scritte piccole: usali solo se servono e controlla con "Prima".'),
        ]);
      case _Tab.background:
        return ListView(padding: pad, children: [
          _section(ctx, 'Sfondo'),
          _slider(ctx, 'Pulisci sfondo scuro', _p.bgClean, 0, 1,
              (v) => _p.copyWith(bgClean: v)),
          _slider(ctx, 'Sfondo bianco', _p.background, 0, 1,
              (v) => _p.copyWith(background: v)),
          _help(
              ctx,
              widget.photo.subject != null
                  ? 'Scontorno IA attivo: cambia solo lo sfondo, l\'orologio resta com\'è.'
                  : 'Scontorno IA: $_cutoutState. Senza IA lo sfondo bianco '
                      'funziona solo su sfondi già chiari.'),
          _section(ctx, 'Formato'),
          SwitchListTile(
            title: const Text('Ritaglio quadrato 1:1'),
            subtitle: const Text('Centrato sul quadrante, per annunci e Instagram'),
            value: _p.square,
            onChanged: (v) => setState(() => _p = _p.copyWith(square: v)),
          ),
        ]);
    }
  }

  /// Cursore: nome e valore su una riga, cursore a tutta larghezza sotto.
  /// Doppio tocco sul nome = valore di partenza ([reset]).
  Widget _slider(BuildContext ctx, String label, double value, double min,
      double max, EnhanceParams Function(double) apply,
      {bool enabled = true, double reset = 0}) {
    final t = Theme.of(ctx).textTheme;
    final cs = Theme.of(ctx).colorScheme;
    final shown = (value * 100).round();
    final valueText = min < 0 && shown > 0 ? '+$shown' : '$shown';
    final fg = enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.38);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: enabled ? () => _update(apply(reset), now: true) : null,
          child: ExcludeSemantics(
            child: Row(children: [
              Expanded(child: Text(label, style: t.bodyMedium?.copyWith(color: fg))),
              Text(valueText,
                  style: t.labelLarge?.copyWith(
                    color: enabled ? cs.primary : fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ]),
          ),
        ),
        Semantics(
          label: label,
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            semanticFormatterCallback: (v) => valueText,
            onChanged: enabled ? (v) => _update(apply(v)) : null,
          ),
        ),
      ]),
    );
  }
}

/// Pulsante "tieni premuto per vedere l'originale".
class _HoldButton extends StatefulWidget {
  final String label;
  final ValueChanged<bool> onHold;
  const _HoldButton({required this.label, required this.onHold});

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
    widget.onHold(v);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Tieni premuto per vedere la foto originale',
      onTap: () {
        // con il lettore di schermo: alterna originale e ritocco
        _set(!_down);
      },
      child: ExcludeSemantics(
        child: Listener(
          onPointerDown: (_) => _set(true),
          onPointerUp: (_) => _set(false),
          onPointerCancel: (_) => _set(false),
          child: AnimatedContainer(
            duration: Motion.fast,
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            decoration: BoxDecoration(
              color: _down
                  ? Colors.white.withValues(alpha: 0.92)
                  : Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.compare, size: 20, color: _down ? Colors.black : Colors.white),
              const SizedBox(width: Space.s),
              Text(widget.label,
                  style: t.labelLarge?.copyWith(
                      color: _down ? Colors.black : Colors.white)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final Dial dial;
  final DialShape? shape;
  final bool showDial;
  final bool square;
  final int imgW, imgH;
  final Color color;

  _OverlayPainter({
    required this.dial,
    required this.shape,
    required this.showDial,
    required this.square,
    required this.imgW,
    required this.imgH,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (square) {
      // stessa regola di cropSquare, in coordinate dello schermo
      final side = math.min(imgW, imgH);
      final sh = shape;
      final ccx = sh != null ? sh.centroid.x : dial.cx;
      final ccy = sh != null ? sh.centroid.y : dial.cy;
      final x0 = (ccx * imgW - side / 2).round().clamp(0, imgW - side);
      final y0 = (ccy * imgH - side / 2).round().clamp(0, imgH - side);
      final sx = size.width / imgW, sy = size.height / imgH;
      final rect = Rect.fromLTWH(x0 * sx, y0 * sy, side * sx, side * sy);
      final dim = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(rect);
      canvas.drawPath(dim, Paint()..color = Colors.black45);
      canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.white70);
    }
    final sh = shape;
    if (showDial && sh != null) {
      final path = Path();
      for (var i = 0; i < sh.length; i++) {
        final o = Offset(sh.pts[2 * i] * size.width, sh.pts[2 * i + 1] * size.height);
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      path.close();
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = Colors.black38);
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color);
    } else if (showDial) {
      final c = Offset(dial.cx * size.width, dial.cy * size.height);
      final r = dial.r * math.min(size.width, size.height);
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = Colors.black38);
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color);
      canvas.drawCircle(c, 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      old.dial != dial ||
      old.shape != shape ||
      old.showDial != showDial ||
      old.square != square ||
      old.color != color;
}
