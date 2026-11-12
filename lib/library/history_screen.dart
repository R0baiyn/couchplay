import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_screen.dart';
import '../catalog/versions.dart';
import '../focus_ring.dart';
import '../format.dart';
import '../server/models.dart';
import 'library.dart';
import 'library_store.dart';

/// « Historique » : une ligne par film ou par épisode lu, du plus récent au
/// plus ancien, retirés de « Continuer à regarder » et vus compris.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La progression seule ; build ne tourne qu'à son changement, le tri
    // aussi.
    final entries = ref.watch(libraryProvider.select((l) => l.history));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        actions: [
          if (entries.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClear(context, ref),
              child: const Text('Effacer l\'historique'),
            ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Text('Rien regardé pour l\'instant'))
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) =>
                  _HistoryRow(key: ValueKey(entries[i].item.key), entries[i]),
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Effacer l\'historique ?'),
        content: const Text(
          'Les reprises et les marques « vu » sont perdues. '
          'Ma liste reste intacte.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (clear ?? false) await ref.read(libraryProvider.notifier).clearHistory();
  }
}

/// De quoi ouvrir la fiche : celle du film, ou celle de la série pour un
/// épisode. Elle recharge le reste depuis le serveur.
CatalogEntry historyEntry(PlayItem item) => CatalogEntry([
  CatalogItem(
    kind: item.isEpisode ? ContentKind.series : ContentKind.movies,
    id: item.seriesId ?? item.id,
    name: item.name,
    poster: item.poster,
  ),
]);

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
                item.isEpisode
                    ? '${item.name} · S${item.season}E${item.episode}'
                    : item.name,
              ),
            ),
            subtitle: Text(
              '${item.episodeTitle == null ? '' : '${item.episodeTitle} · '}'
              '${formatDate(entry.updatedAt)} · $state',
            ),
            // La fiche : celle du film, ou celle de la série pour un épisode. Elle
            // recharge le reste depuis le serveur.
            onTap: () => openDetails(context, historyEntry(item)),
          ),
        ),
        IconButton(
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
