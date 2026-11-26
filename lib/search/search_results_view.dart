import 'package:flutter/material.dart';

import '../catalog/catalog_screen.dart';
import '../catalog/poster_grid.dart';
import '../catalog/versions.dart';
import '../focus_ring.dart';
import '../focus_scroll.dart';
import '../live/channel.dart';
import '../live/channel_list_view.dart';
import '../live/live_player_screen.dart';
import 'search_index.dart';

/// Puces « Tout / Films / Séries / TV », en haut des résultats.
class SearchFilterBar extends StatelessWidget {
  const SearchFilterBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final SearchFilter selected;
  final ValueChanged<SearchFilter> onSelected;

  @override
  Widget build(BuildContext context) => SmoothFocusGroup(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in SearchFilter.values)
              ChoiceChip(
                key: ValueKey('search.filter.${filter.name}'),
                label: FocusRing(
                  child: Text(switch (filter) {
                    SearchFilter.all => 'Tout',
                    SearchFilter.movies => 'Films',
                    SearchFilter.series => 'Séries',
                    SearchFilter.live => 'TV',
                  }),
                ),
                selected: filter == selected,
                onSelected: (_) => onSelected(filter),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Résultats en sections, dans l'ordre de [sections] (voir [searchSections]),
/// en une seule liste qui défile ; les affiches et les rangées ne sont
/// construites qu'à l'écran. Une chaîne ouvre le lecteur, zapping dans les
/// chaînes trouvées.
class SearchResults extends StatelessWidget {
  const SearchResults({
    super.key,
    required this.sections,
    required this.movies,
    required this.series,
    required this.channels,
  });

  final List<SearchFilter> sections;
  final List<CatalogEntry> movies;
  final List<CatalogEntry> series;
  final List<Channel> channels;

  @override
  Widget build(BuildContext context) {
    void open(CatalogEntry entry) => openDetails(context, entry);
    Widget title(Key key, String title, int count) => SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(
          key: key,
          '$title ($count)',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
    Widget posters(Key key, String name, List<CatalogEntry> entries) =>
        SliverMainAxisGroup(
          slivers: [
            title(key, name, entries.length),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverPosterGrid(entries: entries, onOpen: open),
            ),
          ],
        );
    Widget live() => SliverMainAxisGroup(
      slivers: [
        title(
          const ValueKey('search.sectionChannels'),
          'Chaînes',
          channels.length,
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          sliver: SliverFixedExtentList.builder(
            itemExtent: ChannelTile.height,
            itemCount: channels.length,
            itemBuilder: (context, i) => ChannelTile(
              key: ObjectKey(channels[i]),
              channel: channels[i],
              guide: false,
              onOpen: () => openLivePlayer(context, channels[i], channels),
            ),
          ),
        ),
      ],
    );
    return SmoothFocusGroup(
      child: CustomScrollView(
        key: const ValueKey('search.results'),
        slivers: [
          for (final section in sections)
            switch (section) {
              SearchFilter.movies => posters(
                const ValueKey('search.sectionMovies'),
                'Films',
                movies,
              ),
              SearchFilter.series => posters(
                const ValueKey('search.sectionSeries'),
                'Séries',
                series,
              ),
              SearchFilter.live || SearchFilter.all => live(),
            },
        ],
      ),
    );
  }
}
