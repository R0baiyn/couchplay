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

/// Ligne d'un épisode de la fiche série. Surveille sa seule progression : la
/// fiche, montée sous le lecteur, ne se refait pas à chaque enregistrement
/// (toutes les 10 s).
///
/// Grand écran : vignette, titre, durée et résumé (3 lignes) dans la zone
/// qui lance la lecture, l'icône de téléchargement et le menu ⋮ à droite.
/// Téléphone : vignette, titre et durée, l'état du téléchargement (une fois
/// lancé) et le menu ⋮ (vu, télécharger) en haut ; le résumé entier dessous,
/// sur toute la largeur.
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
    // Raison d'un échec, en texte : l'infobulle du bouton ne s'atteint ni
    // au doigt ni à la télécommande.
    final failure = key == null
        ? null
        : ref.watch(
            downloadsProvider.select(
              (s) => s.entries[key]?.status == DownloadStatus.failed
                  ? s.entries[key]?.error
                  : null,
            ),
          );
    final phone = MediaQuery.sizeOf(context).width < railMinWidth;
    final download = phone && !ref.watch(televisionProvider)
        ? watchDownloadAction(context, ref, item)
        : null;
    final theme = Theme.of(context);
    final e = episode;
    final minutes = e.duration?.inMinutes;
    final watched = progress?.watched ?? false;
    final fraction = progress?.fraction ?? 0;
    final onWatched = this.onWatched;

    final thumbnail = SizedBox(
      width: phone ? 120 : 160,
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
                  child: LinearProgressIndicator(value: fraction),
                ),
            ],
          ),
        ),
      ),
    );
    final title = Row(
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
    );
    final duration = minutes != null && minutes > 0
        ? Text('$minutes min', style: theme.textTheme.bodySmall)
        : null;
    final plot = switch (e.plot) {
      final plot? => Text(
        plot,
        maxLines: phone ? null : 3,
        overflow: phone ? null : TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      null => null,
    };
    final error = failure == null
        ? null
        : Text(
            failure,
            key: ValueKey('catalog.episodeError.${e.id}'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          );

    // Zone qui lance la lecture.
    final play = InkWell(
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
              thumbnail,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    title,
                    ?duration,
                    if (!phone) ...[?plot, ?error],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Menu plutôt qu'appui long : il marche aussi au clavier et à la
    // télécommande.
    // Sans fichier connu ([onWatched] `null`), rien à proposer.
    final menu = onWatched == null
        ? null
        : PopupMenuButton<bool>(
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
              if (download != null)
                PopupMenuItem(
                  key: const ValueKey('catalog.episodeDownloadItem'),
                  // Sans valeur : `onSelected` ne reçoit que vu / non vu.
                  onTap: download.onPressed,
                  enabled: download.onPressed != null,
                  child: FocusRing(
                    child: Row(
                      spacing: 12,
                      children: [download.icon, Text(download.label)],
                    ),
                  ),
                ),
            ],
          );

    // Le menu à côté de la zone qui lance la lecture, pas dedans : → depuis
    // l'épisode l'atteint (télécommande, clavier). Dedans, il n'était ni à
    // sa droite ni dessous pour les flèches.
    final top = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: play),
        if (!phone)
          DownloadButton(
            key: ValueKey('catalog.episodeDownload.${e.id}'),
            item: item,
            compact: true,
          ),
        // Une fois lancé, l'état se voit sans ouvrir le menu.
        if (download != null && download.status != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              key: ValueKey('catalog.episodeStatus.${e.id}'),
              label: download.label,
              child: download.icon,
            ),
          ),
        ?menu,
      ],
    );
    return Card(
      key: ValueKey('catalog.episodeCard.${e.id}'),
      clipBehavior: Clip.antiAlias,
      child: !phone || (plot == null && error == null)
          ? top
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                top,
                // Le résumé lance aussi la lecture, sans arrêt de plus pour
                // le focus.
                InkWell(
                  canRequestFocus: false,
                  onTap: onPlay,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [?plot, ?error],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
