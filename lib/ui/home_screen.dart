import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/codec.dart';
import 'batch_screen.dart';
import 'editor_screen.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _picker = ImagePicker();
  bool _loading = false;

  /// Galleria: una o più foto. Con più foto si apre la modalità serie.
  Future<void> _pickGallery() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 100, limit: 30);
      if (files.isEmpty || !mounted) return;
      if (files.length == 1) return _open(files.first);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BatchScreen(files: files),
      ));
    } catch (e) {
      if (mounted) _snack('Errore: $e');
    }
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 100);
      if (file == null) return;
      await _open(file);
    } catch (e) {
      if (mounted) _snack('Errore: $e');
    }
  }

  Future<void> _open(XFile file) async {
    try {
      setState(() => _loading = true);
      final bytes = await file.readAsBytes();
      final photo = await compute(loadPhoto, bytes);
      if (!mounted) return;
      setState(() => _loading = false);
      if (photo == null) {
        _snack('Non riesco a leggere questa foto. Prova con un JPG.');
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EditorScreen(photo: photo),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Errore: $e');
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? Center(
                child: Semantics(
                  liveRegion: true,
                  child: const Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: Space.l),
                    Text('Preparo la foto…'),
                  ]),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  // testo leggibile anche su tablet
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        Space.xl, Space.xxl, Space.xl, Space.l),
                    children: [
                      Row(children: [
                        ExcludeSemantics(
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Brand.blue,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.auto_awesome,
                                color: Brand.paper, size: 28),
                          ),
                        ),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text('D. Photo Watch Lab', style: t.headlineSmall),
                          ),
                        ),
                      ]),
                      const SizedBox(height: Space.m),
                      Text(
                        'Migliora le foto dei tuoi orologi da mettere in vendita. '
                        'Tutto sul telefono: le foto non vengono caricate da nessuna parte.',
                        style: t.bodyLarge,
                      ),
                      const SizedBox(height: Space.xl),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56)),
                        onPressed: _pickGallery,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Scegli le foto'),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.s),
                        child: Text(
                          'Puoi sceglierne fino a 30: le migliora tutte insieme.',
                          textAlign: TextAlign.center,
                          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56)),
                        onPressed: () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Scatta ora'),
                      ),
                      const SizedBox(height: Space.xl),
                      Card(
                        elevation: 0,
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                        child: Padding(
                          padding: const EdgeInsets.all(Space.l),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                header: true,
                                child: Text('Per foto che vendono', style: t.titleMedium),
                              ),
                              const SizedBox(height: Space.m),
                              const _Tip(Icons.wb_sunny_outlined,
                                  'Luce di una finestra di lato, mai sole diretto né flash.'),
                              const _Tip(Icons.dark_mode_outlined,
                                  'Fai riflettere nel vetro qualcosa di nero, non il cielo.'),
                              const _Tip(Icons.camera_outlined,
                                  'Un filtro polarizzatore a clip toglie quasi tutti i riflessi.'),
                              const _Tip(Icons.cleaning_services_outlined,
                                  'Vetro pulito con un panno in microfibra.'),
                              const _Tip(Icons.schedule_outlined,
                                  'Lancette sulle 10:10: è la posa classica.'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.xxl),
                      Center(
                        child: Text("un'app Dom Studio",
                            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Tip(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ExcludeSemantics(child: Icon(icon, size: 20, color: cs.primary)),
        const SizedBox(width: Space.m),
        Expanded(child: Text(text)),
      ]),
    );
  }
}
