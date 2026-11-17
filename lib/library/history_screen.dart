import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_screen.dart';
import '../catalog/versions.dart';
import '../confirm.dart';
import '../focus_ring.dart';
import '../format.dart';
import 'library.dart';
import 'library_store.dart';

/// « Historique » : une ligne par film ou par épisode lu, du plus récent au
/// plus ancien, retirés de « Continuer à regarder » et vus compris.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La progression seule (même map tant qu'elle ne change pas) : un favori
    // ajouté ne refait ni l'écran ni le tri.
    final progress = ref.watch(libraryProvider.select((l) => l.progress));
    final entries = Library(progress: progress).history;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        actions: [
          if (entries.isNotEmpty)
            TextButton(
              key: const ValueKey('library.historyClear'),
              onPressed: () => _confirmClear(context, ref),
              child: const Text('Effacer l\'historique'),
            ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(
              child: Text(
                'Rien regardé pour l\'instant',
                key: ValueKey('library.historyEmpty'),
              ),
            )
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) =>
                  _HistoryRow(key: ValueKey(entries[i].item.key), entries[i]),
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final clear = await confirm(
      context,
      title: 'Effacer l\'historique ?',
      content:
          'Les reprises et les marques « vu » sont perdues. '
          'Ma liste reste intacte.',
      action: 'Effacer',
      focusCancel: true,
    );
    if (clear) await ref.read(libraryProvider.notifier).clearHistory();
  }
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow(this.entry, {super.key});

  final Progress entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = entry.item;
    final state = entry.finished
        ? 'Vu'
        : '${formatTime(entry.position)}'
              '${entry.duration > Duration.zero ? ' / ${formatTime(entry.duration)}' : ''}';
    // La ✕ à côté de la ligne et non en `trailing` : dedans, elle serait
    // dans le rectangle de la ligne, et → ne la trouverait pas (télécommande).
    return Row(
      children: [
        Expanded(
          child: ListTile(
            title: FocusRing(
              child: Text(
                item.shortTitle,
                key: ValueKey('library.historyRow.${item.key}'),
              ),
            ),
            subtitle: Text(
              '${item.episodeTitle == null ? '' : '${item.episodeTitle} · '}'
              '${formatDate(entry.updatedAt)} · $state',
            ),
            // La fiche : celle du film, ou celle de la série pour un épisode. Elle
            // recharge le reste depuis le serveur.
            onTap: () => openDetails(
              context,
              CatalogEntry([item.catalogItem]),
              episode: item.isEpisode ? item : null,
            ),
          ),
        ),
        IconButton(
          key: ValueKey('library.historyRemove.${item.key}'),
          tooltip: 'Retirer de l\'historique',
          icon: const Icon(Icons.close),
          onPressed: () =>
              ref.read(libraryProvider.notifier).removeProgress(item.key),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
