import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../focus_ring.dart';
import '../format.dart';
import '../library/library_store.dart';
import 'player_launch.dart';
import '../downloads/download.dart';
import '../downloads/download_button.dart';
import '../downloads/downloads.dart';
import 'downloads_poster.dart';
import '../downloads/export.dart';
import '../downloads/offline_list.dart';

/// Un film prêt, seul dans sa carte.
class ReadyMovie extends StatelessWidget {
  const ReadyMovie({super.key, required this.download});

  final Download download;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    clipBehavior: Clip.antiAlias,
    child: _ReadyRow(download: download),
  );
}

/// Une série : son affiche, son nom, le nombre d'épisodes et leur taille,
/// puis ses épisodes prêts dans l'ordre (saison, numéro).
class ReadySeries extends StatelessWidget {
  const ReadySeries({super.key, required this.episodes});

  final List<Download> episodes;

  @override
  Widget build(BuildContext context) {
    final sorted = sortedEpisodes(episodes);
    final first = sorted.first.item;
    final size = totalSize(episodes);
    final count = episodes.length;
    return Card(
      key: ValueKey('downloads.seriesCard.${first.seriesId}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              spacing: 12,
              children: [
                DownloadPoster(first, width: 56),
                Expanded(
                  child: Text(
                    '${first.name} · $count '
                    '${count > 1 ? 'épisodes' : 'épisode'} · '
                    '${formatSize(size)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          for (final d in sorted) _ReadyRow(key: ValueKey(d.key), download: d),
        ],
      ),
    );
  }
}

/// Une vidéo prête : appui = lecture, ⤓ = export (PC), poubelle =
/// suppression. Un film a sa vignette ; un épisode est sous celle de sa
/// série. Où on en est : barre de visionnage, « Reprendre à … », coche si
/// vu (bibliothèque locale, sans serveur).
class _ReadyRow extends ConsumerStatefulWidget {
  const _ReadyRow({super.key, required this.download});

  final Download download;

  @override
  ConsumerState<_ReadyRow> createState() => _ReadyRowState();
}

class _ReadyRowState extends ConsumerState<_ReadyRow> {
  /// Copie en cours : l'action est désactivée.
  var _exporting = false;

  /// Copie la vidéo dans un dossier choisi, sous son vrai titre. Une vidéo
  /// effacée entre-temps (« Effacer une fois vu », suppression) est dite,
  /// pas avalée.
  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    final item = widget.download.item;
    // Grisé dès le choix du dossier : sous Linux, il ne bloque pas la
    // fenêtre, et un second appui lancerait un second export.
    setState(() => _exporting = true);
    try {
      final String? path;
      try {
        path = await ref.read(pickFolderProvider)();
      } on Exception {
        say("Impossible d'ouvrir le choix du dossier.");
        return;
      }
      if (path == null || !mounted) return;
      final source = ref.read(downloadsProvider.notifier).fileOf(item);
      if (source == null) {
        say("La vidéo n'existe plus.");
        return;
      }
      await exportVideo(source, Directory(path), exportFileName(item));
      say('Exporté dans $path');
    } on ExportException catch (e) {
      say(e.message);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final download = widget.download;
    final item = download.item;
    final episode = item.isEpisode;
    final theme = Theme.of(context);
    final progress = ref.watch(
      libraryProvider.select((l) => l.progress[item.key]),
    );
    // Où on en est, en texte et en coche seulement (D-046).
    final watched = progress?.watched ?? false;
    final resume = progress?.resumeAt;
    final subtitle = _exporting
        ? 'Export en cours · ${formatSize(download.size)}'
        : [
            formatSize(download.size),
            if (resume != null) 'Reprendre à ${formatTime(resume)}',
          ].join(' · ');
    return Row(
      key: ValueKey('downloads.readyRow.${download.key}'),
      children: [
        Expanded(
          child: InkWell(
            key: ValueKey('downloads.open.${download.key}'),
            onTap: () => openPlayer(context, ref, item),
            child: FocusRing(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  spacing: 12,
                  children: [
                    if (!episode) DownloadPoster(item),
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
                                  key: ValueKey(
                                    'downloads.watched.${download.key}',
                                  ),
                                  Icons.check_circle,
                                  size: 18,
                                  semanticLabel: 'Vu',
                                  color: theme.colorScheme.primary,
                                ),
                              Flexible(
                                child: Text(
                                  episode
                                      ? 'S${item.season}E${item.episode}'
                                            '${item.episodeTitle == null ? '' : ' · ${item.episodeTitle}'}'
                                      : item.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: episode
                                      ? theme.textTheme.bodyMedium
                                      : theme.textTheme.titleSmall,
                                ),
                              ),
                            ],
                          ),
                          Text(subtitle, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (ref.watch(desktopFilesProvider))
          IconButton(
            key: ValueKey('downloads.export.${download.key}'),
            tooltip: 'Exporter la vidéo',
            icon: const Icon(Icons.save_alt),
            onPressed: _exporting ? null : _export,
          ),
        IconButton(
          key: ValueKey('downloads.delete.${download.key}'),
          tooltip: 'Supprimer la vidéo',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => confirmDelete(context, ref, download),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
