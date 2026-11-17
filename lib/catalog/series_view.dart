import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../downloads/download.dart';
import '../downloads/download_button.dart';
import '../downloads/downloads.dart';
import '../focus_ring.dart';
import '../library/library.dart';
import '../library/library_store.dart';
import '../server/models.dart';
import '../television.dart';
import 'poster_grid.dart';

/// « Télécharger la saison » : met en file, dans l'ordre, les épisodes de la
/// saison affichée qui ne sont ni téléchargés ni déjà en file (ceux en échec
/// repartent).
class SeasonDownloadButton extends ConsumerWidget {
  const SeasonDownloadButton({super.key, required this.items});

  final List<PlayItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty || ref.watch(televisionProvider)) {
      return const SizedBox.shrink();
    }
    // Deux chiffres seulement : l'avancement ne reconstruit pas le bouton.
    final (missing, ready) = ref.watch(
      downloadsProvider.select((s) {
        var missing = 0;
        var ready = 0;
        for (final item in items) {
          final status = s.entries[item.key]?.status;
          if (status == null || status == DownloadStatus.failed) missing++;
          if (status == DownloadStatus.ready) ready++;
        }
        return (missing, ready);
      }),
    );
    return OutlinedButton.icon(
      icon: Icon(
        missing > 0
            ? Icons.download_outlined
            : ready == items.length
            ? Icons.download_done
            : Icons.schedule,
      ),
      label: Text(
        missing > 0
            ? 'Télécharger la saison'
            : ready == items.length
            ? 'Saison téléchargée'
            : 'Saison en file',
      ),
      onPressed: missing > 0
          ? () => ref.read(downloadsProvider.notifier).add(items)
          : null,
    );
  }
}

/// Surveille sa seule progression : la fiche, montée sous le lecteur, ne se
/// refait pas à chaque enregistrement (toutes les 10 s).
class EpisodeTile extends ConsumerWidget {
  const EpisodeTile({
    super.key,
    this.focusNode,
    required this.episode,
    required this.item,
    required this.onPlay,
    required this.onWatched,
  });

  final FocusNode? focusNode;
  final Episode episode;

  /// `null` si le fichier de l'épisode est inconnu : ni lecture ni suivi.
  final PlayItem? item;

  /// `null` si le fichier de l'épisode est inconnu.
  final VoidCallback? onPlay;
  final ValueChanged<bool>? onWatched;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = item?.key;
    final progress = key == null
        ? null
        : ref.watch(libraryProvider.select((l) => l.progress[key]));
    final theme = Theme.of(context);
    final e = episode;
    final minutes = e.duration?.inMinutes;
    final watched = progress?.watched ?? false;
    final fraction = progress?.fraction ?? 0;
    final onWatched = this.onWatched;
    return Card(
      clipBehavior: Clip.antiAlias,
      // Le menu à côté de la zone qui lance la lecture, pas dedans : → depuis
      // l'épisode l'atteint (télécommande, clavier). Dedans, il n'était ni à
      // sa droite ni dessous pour les flèches.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              key: ValueKey('catalog.episode.${episode.id}'),
              focusNode: focusNode,
              onTap: onPlay,
              // Rayon de la carte, qui coupe ce qui dépasse.
              child: FocusRing(
                radius: 12,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      SizedBox(
                        width: 160,
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                PosterImage(url: e.image, icon: Icons.tv),
                                // Commencé : où on en est, en bas de la vignette.
                                if (!watched && fraction > 0)
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: LinearProgressIndicator(
                                      value: fraction,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 4,
                          children: [
                            Row(
                              spacing: 6,
                              children: [
                                if (watched)
                                  Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    semanticLabel: 'Vu',
                                    color: theme.colorScheme.primary,
                                  ),
                                Expanded(
                                  child: Text(
                                    '${e.number}. ${e.title}',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ),
                              ],
                            ),
                            if (minutes != null && minutes > 0)
                              Text(
                                '$minutes min',
                                style: theme.textTheme.bodySmall,
                              ),
                            if (e.plot case final plot?)
                              Text(
                                plot,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          DownloadButton(
            key: ValueKey('catalog.episodeDownload.${e.id}'),
            item: item,
            compact: true,
          ),
          // Menu plutôt qu'appui long : il marche aussi au clavier et à la
          // télécommande.
          if (onWatched != null)
            PopupMenuButton<bool>(
              key: ValueKey('catalog.episodeMenu.${e.id}'),
              tooltip: "Plus d'options",
              onSelected: onWatched,
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: const ValueKey('catalog.episodeToggleWatched'),
                  value: !watched,
                  child: FocusRing(
                    child: Text(
                      watched ? 'Marquer comme non vu' : 'Marquer comme vu',
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
