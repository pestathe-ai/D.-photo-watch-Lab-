import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/codec.dart';
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

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 100);
      if (file == null) return;
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
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Preparo la foto…'),
                ]),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                children: [
                  Row(children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Brand.blue,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.auto_awesome,
                          color: Brand.paper, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text('D. Photo Watch Lab',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Text(
                    'Migliora le foto dei tuoi orologi da mettere in vendita. '
                    'Tutto sul telefono: le foto non vengono caricate da nessuna parte.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Scegli una foto'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Scatta ora'),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Card(
                    elevation: 0,
                    color: cs.secondaryContainer.withValues(alpha: 0.5),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Per foto che vendono',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          SizedBox(height: 8),
                          _Tip('Luce di una finestra, mai sole diretto né flash.'),
                          _Tip('Foglio bianco curvato dietro e sotto l\'orologio.'),
                          _Tip('Vetro pulito con un panno in microfibra.'),
                          _Tip('Telefono parallelo al quadrante, un po\' di lato per non riflettersi.'),
                          _Tip('Lancette sulle 10:10: è la posa classica.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: Text("un'app Dom Studio",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.6))),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final String text;
  const _Tip(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('•  '),
          Expanded(child: Text(text)),
        ]),
      );
}
