import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/favorite_button.dart';
import '../library/library.dart';
import '../library/library_store.dart';
import '../player/player_screen.dart';
import '../server/models.dart';
import 'catalog_providers.dart';
import 'details_view.dart';
import 'poster_grid.dart';
import 'status_views.dart';

/// Fiche d'une série : en-tête, choix de la saison, liste des épisodes.
class SeriesScreen extends ConsumerStatefulWidget {
  const SeriesScreen({super.key, required this.item});

  final CatalogItem item;

  @override
  ConsumerState<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends ConsumerState<SeriesScreen> {
  int? _season;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = seriesDetailsProvider(widget.item.id);
    return Scaffold(
      appBar: DetailsAppBar(
        scroll: _scroll,
        child: AppBar(
          title: Text(widget.item.name),
          actions: [
            FavoriteButton(
              favoriteKey: 'series:${widget.item.id}',
              name: widget.item.name,
              poster: widget.item.poster,
            ),
          ],
        ),
      ),
      body: switch (ref.watch(provider)) {
        AsyncData(:final value) => _content(value),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(provider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _content(SeriesDetails series) {
    // Première saison numérotée par défaut, les épisodes spéciaux après.
    final season =
        series.seasons.where((s) => s.number == _season).firstOrNull ??
        series.seasons.where((s) => s.number > 0).firstOrNull ??
        series.seasons.firstOrNull;
    final progress = ref.watch(libraryProvider.select((l) => l.progress));
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(child: DetailsHeader(details: series.details)),
        if (season == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucun épisode disponible.'),
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FocusTraversalGroup(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in series.seasons)
                      ChoiceChip(
                        label: Text(s.name),
                        selected: s == season,
                        onSelected: (_) => setState(() => _season = s.number),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            sliver: SliverList.builder(
              itemCount: season.episodes.length,
              itemBuilder: (context, index) {
                final episode = season.episodes[index];
                final extension = episode.extension;
                // Sans fichier connu, ni lecture ni suivi possibles.
                final item = extension == null
                    ? null
                    : PlayItem.episode(
                        id: episode.id,
                        extension: extension,
                        name: widget.item.name,
                        seriesId: widget.item.id,
                        season: season.number,
                        episode: episode.number,
                        episodeTitle: episode.title,
                        poster: widget.item.poster,
                      );
                return _EpisodeTile(
                  episode: episode,
                  progress: item == null ? null : progress[item.key],
                  onPlay: item == null
                      ? null
                      : () => openPlayer(context, ref, item),
                  onWatched: item == null
                      ? null
                      : (watched) => ref
                            .read(libraryProvider.notifier)
                            .setWatched(item, watched: watched),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.progress,
    required this.onPlay,
    required this.onWatched,
  });

  final Episode episode;
  final Progress? progress;

  /// `null` si le fichier de l'épisode est inconnu.
  final VoidCallback? onPlay;
  final ValueChanged<bool>? onWatched;

  @override
  Widget build(BuildContext context) {
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
              onTap: onPlay,
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
          // Menu plutôt qu'appui long : il marche aussi au clavier et à la
          // télécommande.
          if (onWatched != null)
            PopupMenuButton<bool>(
              tooltip: "Plus d'options",
              onSelected: onWatched,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: !watched,
                  child: Text(
                    watched ? 'Marquer comme non vu' : 'Marquer comme vu',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
