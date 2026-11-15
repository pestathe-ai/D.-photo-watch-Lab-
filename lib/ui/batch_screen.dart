import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;

import '../core/codec.dart';
import '../core/params.dart';
import '../services/cutout.dart';
import 'editor_screen.dart';

class _Item {
  final XFile file;
  Analysis? analysis;
  EnhanceParams? params;
  Uint8List? thumb;
  SubjectMask? subject;
  bool dialFound = false;
  bool failed = false;
  bool busy = false;

  _Item(this.file);
}

/// Più foto insieme: le migliora tutte in automatico, mostra la griglia,
/// permette di ritoccarne una a mano e salva o condivide tutto.
class BatchScreen extends StatefulWidget {
  final List<XFile> files;
  const BatchScreen({super.key, required this.files});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  late final List<_Item> _items = widget.files.map(_Item.new).toList();
  int _prepared = 0;
  int _cutoutOk = 0;
  String? _exportMsg;
  double _exportProgress = 0;

  bool get _ready => _prepared == _items.length;

  @override
  void initState() {
    super.initState();
    _prepareAll();
  }

  Future<void> _prepareAll() async {
    for (final it in _items) {
      if (!mounted) return;
      try {
        final bytes = await it.file.readAsBytes();
        final r = await compute(prepareBatchItem, bytes);
        if (r == null) {
          it.failed = true;
        } else {
          it.analysis = r.analysis;
          it.params = r.params;
          it.dialFound = r.dialFound;
          it.subject = await Cutout.maskFor(r.previewJpeg, r.previewW, r.previewH);
          if (it.subject != null) _cutoutOk++;
          it.thumb = await compute(
              runFileRenderJob,
              FileRenderJob(bytes, kPreviewMaxSide, r.analysis,
                  r.params.copyWith(square: false),
                  subject: it.subject, quality: 85));
        }
      } catch (_) {
        it.failed = true;
      }
      if (mounted) setState(() => _prepared++);
    }
  }

  void _snack(String msg, {SnackBarAction? action}) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg), action: action));

  Future<void> _edit(_Item it) async {
    if (it.analysis == null || it.busy) return;
    setState(() => it.busy = true);
    LoadedPhoto? photo;
    try {
      photo = await compute(loadPhoto, await it.file.readAsBytes());
      photo?.subject = it.subject;
    } catch (_) {}
    if (!mounted) return;
    setState(() => it.busy = false);
    if (photo == null) {
      _snack('Non riesco ad aprire questa foto.');
      return;
    }
    var start = it.params!;
    // quadrante non trovato: proponi il cerchio al centro, spento
    if (!it.dialFound && !start.dialOn) start = start.copyWith(dial: const Dial(r: 0.32));
    final result = await Navigator.of(context).push<EnhanceParams>(
      MaterialPageRoute(
        builder: (_) => EditorScreen(photo: photo!, initial: start, batchMode: true),
      ),
    );
    if (result == null || !mounted) return;
    it.params = result;
    it.subject = photo!.subject ?? it.subject;
    it.dialFound = it.dialFound || result.dialOn;
    await _rethumb(it, photo);
    if (!mounted || _items.length < 2) return;
    _snack('Foto aggiornata', action: SnackBarAction(
      label: 'Applica a tutte',
      onPressed: () => _applyToAll(result),
    ));
  }

  Future<void> _rethumb(_Item it, [LoadedPhoto? photo]) async {
    setState(() => it.busy = true);
    try {
      if (photo != null) {
        it.thumb = await compute(
            runRenderJob,
            RenderJob(photo.preview, it.analysis!,
                it.params!.copyWith(square: false), 85,
                subject: it.subject));
      } else {
        final r = await compute(
            runFileRenderJob,
            FileRenderJob(await it.file.readAsBytes(), kPreviewMaxSide,
                it.analysis!, it.params!.copyWith(square: false),
                subject: it.subject, quality: 85));
        if (r != null) it.thumb = r;
      }
    } catch (_) {}
    if (mounted) setState(() => it.busy = false);
  }

  /// Copia le regolazioni (luce, colore, sfondo, intensità del quadrante)
  /// su tutte le foto, lasciando a ognuna il suo cerchio del quadrante.
  Future<void> _applyToAll(EnhanceParams src) async {
    for (final it in _items) {
      if (it.params == null) continue;
      final own = it.params!;
      it.params = src.copyWith(
        dial: own.dial,
        shape: own.shape,
        clearShape: own.shape == null,
        dialOn: src.dialOn && (it.dialFound || own.dialOn),
      );
    }
    setState(() {});
    for (final it in _items) {
      if (!mounted) return;
      if (it.params != null) await _rethumb(it);
    }
  }

  Future<List<File>> _exportAll() async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final out = <File>[];
    final todo = _items.where((e) => e.params != null).toList();
    for (var k = 0; k < todo.length; k++) {
      if (!mounted) break;
      setState(() {
        _exportMsg = 'Preparo la foto ${k + 1} di ${todo.length}…';
        _exportProgress = k / todo.length;
      });
      final it = todo[k];
      final bytes = await compute(
          runFileRenderJob,
          FileRenderJob(await it.file.readAsBytes(), kExportMaxSide,
              it.analysis!, it.params!,
              subject: it.subject));
      if (bytes == null) continue;
      final f = File('${dir.path}/dphotowatch_${stamp}_${k + 1}.jpg');
      await f.writeAsBytes(bytes, flush: true);
      out.add(f);
    }
    if (mounted) setState(() => _exportMsg = null);
    return out;
  }

  Future<void> _saveAll() async {
    try {
      final files = await _exportAll();
      if (!await Gal.hasPermission(toAlbum: true)) {
        await Gal.requestPermission(toAlbum: true);
      }
      for (final f in files) {
        await Gal.putImage(f.path, album: 'D. Photo Watch Lab');
      }
      if (mounted) {
        _snack('${files.length} foto salvate (album "D. Photo Watch Lab")');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _exportMsg = null);
        _snack('Errore nel salvataggio: $e');
      }
    }
  }

  Future<void> _shareAll() async {
    try {
      final files = await _exportAll();
      if (files.isEmpty) return;
      await SharePlus.instance.share(
          ShareParams(files: files.map((f) => XFile(f.path)).toList()));
    } catch (e) {
      if (mounted) {
        setState(() => _exportMsg = null);
        _snack('Errore: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final exporting = _exportMsg != null;
    final found = _items.where((e) => e.dialFound).length;
    return PopScope(
      canPop: !exporting,
      child: Scaffold(
        appBar: AppBar(title: Text('${_items.length} foto')),
        body: SafeArea(
          child: Column(children: [
            if (!_ready) ...[
              LinearProgressIndicator(value: _prepared / _items.length),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Miglioro le foto: $_prepared di ${_items.length}'),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(
                  '${found == _items.length ? 'Quadrante trovato in tutte le foto. Tocca una foto per ritoccarla.' : 'Quadrante trovato in $found foto su ${_items.length}: tocca quelle con il segnale arancio per posizionarlo tu.'}'
                  '${_cutoutOk == _items.length ? '' : '\nScontorno IA riuscito in $_cutoutOk su ${_items.length}${Cutout.lastError != null ? ' (${Cutout.lastError})' : ''}.'}',
                  textAlign: TextAlign.center,
                ),
              ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: _items.length,
                itemBuilder: (_, i) => _tile(_items[i]),
              ),
            ),
            if (exporting) ...[
              LinearProgressIndicator(value: _exportProgress),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_exportMsg!),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _ready && !exporting ? _shareAll : null,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Condividi'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _ready && !exporting ? _saveAll : null,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Salva tutte'),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tile(_Item it) {
    final cs = Theme.of(context).colorScheme;
    Widget child;
    if (it.failed) {
      child = const Center(child: Text('Foto non leggibile'));
    } else if (it.thumb == null) {
      child = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else {
      child = Image.memory(it.thumb!, fit: BoxFit.cover, gaplessPlayback: true);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Material(
        color: cs.surfaceContainerHighest,
        child: InkWell(
          onTap: it.thumb == null ? null : () => _edit(it),
          child: Stack(fit: StackFit.expand, children: [
            child,
            if (it.thumb != null && !it.dialFound)
              const Positioned(
                right: 6,
                top: 6,
                child: Tooltip(
                  message: 'Quadrante non trovato',
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: Color(0xFFF28C38),
                    child: Icon(Icons.priority_high, size: 16, color: Colors.white),
                  ),
                ),
              ),
            if (it.busy)
              const ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
          ]),
        ),
      ),
    );
  }
}
