import '../focus_scroll.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../focus_ring.dart';
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
  const SeriesScreen({super.key, required this.item, this.episode});

  final CatalogItem item;

  /// Épisode à montrer à l'ouverture : sa saison, la page défilée jusqu'à lui
  /// et le focus dessus (télécommande).
  final PlayItem? episode;

  @override
  ConsumerState<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends ConsumerState<SeriesScreen> {
  late int? _season = widget.episode?.season;
  final _scroll = ScrollController();
  final _target = FocusNode(debugLabel: 'épisode demandé');
  var _revealing = false;

  /// Défile jusqu'à l'épisode demandé puis lui donne le focus. La liste est
  /// paresseuse : tant qu'il n'est pas construit, on avance d'un écran et on
  /// réessaie à l'image suivante.
  void _reveal([int attempt = 0]) {
    if (!mounted || attempt > 40) return;
    final context = _target.context;
    if (context != null) {
      Scrollable.ensureVisible(context, alignment: 0.3);
      _target.requestFocus();
      return;
    }
    if (_scroll.hasClients) {
      _scroll.jumpTo(
        (_scroll.position.pixels + _scroll.position.viewportDimension).clamp(
          0,
          _scroll.position.maxScrollExtent,
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(attempt + 1));
  }

  @override
  void dispose() {
    _target.dispose();
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
              favoriteKey: widget.item.libraryKey,
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
    if (widget.episode != null && !_revealing) {
      _revealing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
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
              child: SmoothFocusGroup(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in series.seasons)
                      ChoiceChip(
                        label: FocusRing(child: Text(s.name)),
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
                  focusNode: episode.id == widget.episode?.id ? _target : null,
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
    this.focusNode,
    required this.episode,
    required this.progress,
    required this.onPlay,
    required this.onWatched,
  });

  final FocusNode? focusNode;
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
          // Menu plutôt qu'appui long : il marche aussi au clavier et à la
          // télécommande.
          if (onWatched != null)
            PopupMenuButton<bool>(
              tooltip: "Plus d'options",
              onSelected: onWatched,
              itemBuilder: (_) => [
                PopupMenuItem(
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
