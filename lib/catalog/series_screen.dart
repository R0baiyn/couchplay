import '../focus_scroll.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../focus_ring.dart';
import '../library/favorite_button.dart';
import '../library/library.dart';
import '../library/library_store.dart';
import '../player/player_launch.dart';
import '../server/models.dart';
import 'catalog_providers.dart';
import 'details_view.dart';
import 'series_view.dart';
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
          title: Text(widget.item.parsedName.display),
          actions: [
            FavoriteButton(
              key: const ValueKey('catalog.favorite'),
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
          key: const ValueKey('catalog.error'),
          error: error,
          onRetry: () => ref.invalidate(provider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  /// L'épisode [episode] de [season] : `null` sans fichier connu, ni lecture
  /// ni suivi possibles.
  PlayItem? _item(Episode episode, Season season) {
    final extension = episode.extension;
    return extension == null
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
  }

  Widget _content(SeriesDetails series) {
    // Première saison numérotée par défaut, les épisodes spéciaux après.
    final season =
        series.seasons.where((s) => s.number == _season).firstOrNull ??
        series.seasons.where((s) => s.number > 0).firstOrNull ??
        series.seasons.firstOrNull;
    // Saison disparue : l'épisode n'y est pas, rien à chercher en défilant.
    final target = widget.episode;
    if (target != null &&
        season != null &&
        season.episodes.any((e) => e.id == target.id) &&
        !_revealing) {
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
              child: Text(
                'Aucun épisode disponible.',
                key: ValueKey('catalog.noEpisodes'),
              ),
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
                        key: ValueKey('catalog.seasonChip.${s.number}'),
                        label: FocusRing(child: Text(s.name)),
                        selected: s == season,
                        onSelected: (_) => setState(() => _season = s.number),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SeasonDownloadButton(
                  key: const ValueKey('catalog.seasonDownload'),
                  items: [
                    for (final episode in season.episodes)
                      ?_item(episode, season),
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
                final item = _item(episode, season);
                return EpisodeTile(
                  focusNode: episode.id == widget.episode?.id ? _target : null,
                  episode: episode,
                  item: item,
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
