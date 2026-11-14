import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;

import '../core/codec.dart';
import '../core/params.dart';
import '../core/pipeline.dart';
import '../services/cutout.dart';

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

  // gesto sul cerchio del quadrante
  Dial? _dialAtStart;
  Offset _focalAtStart = Offset.zero;

  @override
  void initState() {
    super.initState();
    _p = widget.initial ?? autoParamsFor(widget.photo.dialGuess);
    // se il quadrante non è stato trovato, il cerchio parte dal centro
    if (!widget.photo.dialGuess.found && widget.initial == null) {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ritocco'),
        actions: widget.batchMode
            ? [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(_p),
                  icon: const Icon(Icons.check),
                  label: const Text('Fatto'),
                ),
              ]
            : [
          IconButton(
            tooltip: 'Condividi',
            onPressed: _exporting ? null : _share,
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: 'Salva in galleria',
            onPressed: _exporting ? null : _save,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(child: _previewArea()),
          if (_exporting) const LinearProgressIndicator(),
          _tabs(),
          SizedBox(height: 236, child: _controls()),
        ]),
      ),
    );
  }

  Widget _previewArea() {
    final pv = widget.photo.preview;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: pv.width / pv.height,
              child: LayoutBuilder(builder: (context, box) {
                final size = box.biggest;
                return GestureDetector(
                  onLongPressStart: (_) => setState(() => _showOriginal = true),
                  onLongPressEnd: (_) => setState(() => _showOriginal = false),
                  onScaleStart: (d) {
                    if (_tab != _Tab.dial || !_p.dialOn) return;
                    _dialAtStart = _p.dial;
                    _focalAtStart = d.localFocalPoint;
                  },
                  onScaleUpdate: (d) {
                    final start = _dialAtStart;
                    if (start == null) return;
                    final delta = d.localFocalPoint - _focalAtStart;
                    _update(_p.copyWith(
                      dial: start.copyWith(
                        cx: start.cx + delta.dx / size.width,
                        cy: start.cy + delta.dy / size.height,
                        r: start.r * d.scale,
                      ),
                    ));
                  },
                  onScaleEnd: (_) => _dialAtStart = null,
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
                          showDial: _p.dialOn && _tab == _Tab.dial,
                          square: _p.square,
                          imgW: pv.width,
                          imgH: pv.height,
                          color: cs.secondary,
                        ),
                      ),
                    if (_showOriginal)
                      const Positioned(
                        left: 8,
                        top: 8,
                        child: _Badge('Originale'),
                      ),
                    if (_rendering)
                      const Positioned(
                        right: 8,
                        top: 8,
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ]),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _tab == _Tab.dial && _p.dialOn
              ? 'Trascina il cerchio sul quadrante, pizzica per ridimensionarlo'
              : 'Tieni premuto sulla foto per vedere l\'originale',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }

  Widget _tabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SegmentedButton<_Tab>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: _Tab.auto, label: Text('Auto')),
          ButtonSegment(value: _Tab.light, label: Text('Luce')),
          ButtonSegment(value: _Tab.dial, label: Text('Quadrante')),
          ButtonSegment(value: _Tab.background, label: Text('Sfondo')),
        ],
        selected: {_tab},
        onSelectionChanged: (s) => setState(() => _tab = s.first),
      ),
    );
  }

  Widget _controls() {
    switch (_tab) {
      case _Tab.auto:
        return ListView(padding: const EdgeInsets.all(16), children: [
          FilledButton.icon(
            onPressed: () =>
                _update(EnhanceParams.auto.withDial(_p.dial), now: true),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Migliora in un tocco'),
          ),
          const SizedBox(height: 8),
          _slider('Intensità', _p.intensity, 0, 1,
              (v) => _p.copyWith(intensity: v)),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () =>
                _update(EnhanceParams.none.withDial(_p.dial), now: true),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Nessun ritocco'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Colore e livelli automatici'),
            subtitle: const Text('Toglie la dominante gialla/blu e usa tutta la gamma'),
            value: _p.autoColor,
            onChanged: (v) => _update(_p.copyWith(autoColor: v), now: true),
          ),
        ]);
      case _Tab.light:
        return ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
          _slider('Esposizione', _p.exposure, -1, 1,
              (v) => _p.copyWith(exposure: v)),
          _slider('Contrasto', _p.contrast, -1, 1,
              (v) => _p.copyWith(contrast: v)),
          _slider('Calore', _p.warmth, -1, 1, (v) => _p.copyWith(warmth: v)),
          _slider('Schiarisci ombre', _p.shadows, 0, 1,
              (v) => _p.copyWith(shadows: v)),
          _slider('Recupera luci', _p.highlights, 0, 1,
              (v) => _p.copyWith(highlights: v)),
          _slider('Riduci rumore', _p.denoise, 0, 1,
              (v) => _p.copyWith(denoise: v)),
          _slider('Nitidezza', _p.sharpen, 0, 1,
              (v) => _p.copyWith(sharpen: v)),
        ]);
      case _Tab.dial:
        return ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
          SwitchListTile(
            title: const Text('Ritocca il quadrante'),
            value: _p.dialOn,
            onChanged: (v) => _update(_p.copyWith(dialOn: v), now: true),
          ),
          _slider('Ammorbidisci segni', _p.smooth, 0, 1,
              (v) => _p.copyWith(smooth: v),
              enabled: _p.dialOn),
          _slider('Anti-riflesso vetro', _p.glare, 0, 1,
              (v) => _p.copyWith(glare: v),
              enabled: _p.dialOn),
          _slider('Togli polvere', _p.dust, 0, 1, (v) => _p.copyWith(dust: v),
              enabled: _p.dialOn),
          _slider('Dettaglio', _p.detail, 0, 1, (v) => _p.copyWith(detail: v),
              enabled: _p.dialOn),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Dettaglio rende più incisi indici e scritte, ma mostra anche i '
              'difetti: usalo poco.',
            ),
          ),
        ]);
      case _Tab.background:
        return ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
          _slider('Sfondo bianco', _p.background, 0, 1,
              (v) => _p.copyWith(background: v)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              widget.photo.subject != null
                  ? 'Scontorno IA attivo: schiarisce solo lo sfondo, lascia '
                      'l\'orologio com\'è e tiene un filo d\'ombra naturale.'
                  : 'Scontorno IA: $_cutoutState. Senza IA funziona solo su '
                      'sfondi già chiari (foglio bianco o grigio).',
            ),
          ),
          SwitchListTile(
            title: const Text('Ritaglio quadrato 1:1'),
            subtitle: const Text('Centrato sul quadrante, ideale per annunci e Instagram'),
            value: _p.square,
            onChanged: (v) => setState(() => _p = _p.copyWith(square: v)),
          ),
        ]);
    }
  }

  Widget _slider(String label, double value, double min, double max,
      EnhanceParams Function(double) apply,
      {bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        SizedBox(
          width: 128,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: enabled ? null : Theme.of(context).disabledColor)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            onChanged: enabled ? (v) => _update(apply(v)) : null,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            (value * 100).round().toString(),
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      );
}

class _OverlayPainter extends CustomPainter {
  final Dial dial;
  final bool showDial;
  final bool square;
  final int imgW, imgH;
  final Color color;

  _OverlayPainter({
    required this.dial,
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
      final x0 = (dial.cx * imgW - side / 2).round().clamp(0, imgW - side);
      final y0 = (dial.cy * imgH - side / 2).round().clamp(0, imgH - side);
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
    if (showDial) {
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
      old.showDial != showDial ||
      old.square != square ||
      old.color != color;
}
