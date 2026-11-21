import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../desktop_files.dart';
import '../focus_ring.dart';
import '../logging.dart';

/// Fin du journal (D-058), relue à chaque ouverture de l'écran.
final journalLinesProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => readJournalTail(),
);

/// Dossier du journal, `null` sans journal. Surchargé dans les tests.
final journalFolderProvider = Provider<Directory?>(
  (ref) => journalFile?.parent,
);

/// Le journal de l'app, pour comprendre un problème après coup : les lignes
/// dans leur ordre, la plus récente en bas et visible à l'ouverture (une pile
/// d'erreur se lit sous son message). Flèches haut et bas : défilement, pour
/// la télécommande.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Liste à l'envers (0 = en bas) : la flèche haut remonte vers les lignes
  /// anciennes, donc augmente la position. Au bout, la touche passe : le
  /// focus peut monter vers les boutons.
  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => 1.0,
      LogicalKeyboardKey.arrowDown => -1.0,
      _ => 0.0,
    };
    final position = _scroll.position;
    final target = (position.pixels + step * position.viewportDimension / 3)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (step == 0 || target == position.pixels) return KeyEventResult.ignored;
    _scroll.jumpTo(target);
    return KeyEventResult.handled;
  }

  Future<void> _copy(List<String> lines) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    messenger.showSnackBar(const SnackBar(content: Text('Journal copié.')));
  }

  Future<void> _openFolder(Directory folder) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(openFolderProvider)(folder);
    } on IOException {
      messenger.showSnackBar(
        const SnackBar(content: Text("Impossible d'ouvrir le dossier.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(journalLinesProvider);
    final folder = ref.watch(journalFolderProvider);
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontFamily: 'monospace');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal'),
        actions: [
          TextButton.icon(
            key: const ValueKey('settings.journalCopy'),
            icon: const Icon(Icons.copy),
            label: const Text('Copier'),
            onPressed: switch (lines) {
              AsyncData(:final value) when value.isNotEmpty => () => _copy(
                value,
              ),
              _ => null,
            },
          ),
          // PC seulement : le fichier se trouve et s'envoie à la main.
          if (ref.watch(desktopFilesProvider) && folder != null)
            TextButton.icon(
              key: const ValueKey('settings.journalFolder'),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Ouvrir le dossier'),
              onPressed: () => _openFolder(folder),
            ),
        ],
      ),
      body: switch (lines) {
        AsyncData(:final value) when value.isEmpty => const Center(
          child: Text('Journal vide.'),
        ),
        AsyncData(:final value) => Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: FocusRing(
            child: ListView.builder(
              controller: _scroll,
              reverse: true,
              padding: const EdgeInsets.all(12),
              itemCount: value.length,
              itemBuilder: (context, i) =>
                  Text(value[value.length - 1 - i], style: style),
            ),
          ),
        ),
        AsyncError() => const Center(child: Text('Journal illisible.')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
