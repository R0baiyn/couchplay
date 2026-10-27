import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  Widget build(BuildContext context) {
    final provider = seriesDetailsProvider(widget.item.id);
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.name)),
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
    return CustomScrollView(
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
                return _EpisodeTile(
                  episode: episode,
                  onPlay: extension == null
                      ? null
                      : () => openPlayer(
                          context,
                          ref,
                          kind: ContentKind.series,
                          id: episode.id,
                          extension: extension,
                          title:
                              '${widget.item.name} · ${season.name} · '
                              'Épisode ${episode.number}',
                        ),
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
  const _EpisodeTile({required this.episode, required this.onPlay});

  final Episode episode;

  /// `null` si le fichier de l'épisode est inconnu.
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = episode;
    final minutes = e.duration?.inMinutes;
    return Card(
      clipBehavior: Clip.antiAlias,
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
                    child: PosterImage(url: e.image, icon: Icons.tv),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(
                      '${e.number}. ${e.title}',
                      style: theme.textTheme.titleSmall,
                    ),
                    if (minutes != null && minutes > 0)
                      Text('$minutes min', style: theme.textTheme.bodySmall),
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
    );
  }
}
