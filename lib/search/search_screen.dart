import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../server/status_views.dart';
import '../catalog/versions.dart';
import '../server/models.dart';
import '../settings/settings_screen.dart';
import '../text_entry.dart';
import '../catalog/catalog_index.dart';
import '../live/channel.dart';
import 'search_index.dart';
import 'search_results_view.dart';

/// Onglet Recherche : tout le catalogue visible, films, séries puis chaînes,
/// avec une puce pour n'en voir qu'un type. Les chaînes ne retiennent pas les
/// résultats : elles s'ajoutent quand leur liste est chargée.
///
/// La recherche part 300 ms après la dernière frappe (tout de suite avec
/// Entrée). Si l'index charge encore, elle attend qu'il soit prêt.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.focusNode});

  /// Focus du champ, pour Ctrl+F (voir `HomeShell`).
  final FocusNode? focusNode;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _delay = Duration(milliseconds: 300);

  final _controller = TextEditingController();
  Timer? _timer;
  var _query = '';

  /// Puce choisie : gardée quand le texte change.
  var _filter = SearchFilter.all;

  // Derniers résultats, refaits seulement si un index ou la recherche change.
  KindIndex? _moviesIndex;
  KindIndex? _seriesIndex;
  List<SearchableChannel>? _channelsIndex;
  String? _searched;
  var _movies = const <CatalogEntry>[];
  var _series = const <CatalogEntry>[];
  var _channels = const <Channel>[];

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _run(String text) {
    _timer?.cancel();
    if (text != _query) setState(() => _query = text);
  }

  void _clear() {
    _controller.clear();
    _run('');
  }

  @override
  Widget build(BuildContext context) {
    final movies = ref.watch(catalogIndexProvider(ContentKind.movies));
    final series = ref.watch(catalogIndexProvider(ContentKind.series));
    final channels = ref.watch(channelSearchIndexProvider);
    final words = queryWords(_query);
    // Fini : chargé, ou en échec sans rien à montrer.
    bool settled(AsyncValue<Object?> index) =>
        index.hasValue || (index.hasError && !index.isLoading);
    final theme = Theme.of(context);

    Widget message(Key key, String text) => Center(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
    final loading = Center(
      key: const ValueKey('search.loading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          const CircularProgressIndicator(),
          Text('Chargement du catalogue…', style: theme.textTheme.bodyMedium),
        ],
      ),
    );

    final Widget body;
    if (words.isEmpty) {
      body = message(
        const ValueKey('search.hint'),
        'Tape quelques lettres d\'un film, d\'une série ou d\'une chaîne.',
      );
    } else if (settled(movies) && settled(series)) {
      // Une source en échec n'empêche pas de chercher dans les autres ; les
      // chaînes ne retiennent pas les films et les séries.
      final moviesIndex = movies.value?.value;
      final seriesIndex = series.value?.value;
      final channelsIndex = channels.value;
      if (!identical(moviesIndex, _moviesIndex) ||
          !identical(seriesIndex, _seriesIndex) ||
          !identical(channelsIndex, _channelsIndex) ||
          _query != _searched) {
        _moviesIndex = moviesIndex;
        _seriesIndex = seriesIndex;
        _channelsIndex = channelsIndex;
        _searched = _query;
        _movies = search(moviesIndex?.entries ?? const [], _query);
        _series = search(seriesIndex?.entries ?? const [], _query);
        _channels = searchChannels(channelsIndex ?? const [], _query);
      }
      if (_movies.isNotEmpty || _series.isNotEmpty || _channels.isNotEmpty) {
        final sections = searchSections(
          _filter,
          movies: _movies.isNotEmpty,
          series: _series.isNotEmpty,
          channels: _channels.isNotEmpty,
          channelsPending: !settled(channels),
        );
        body = Column(
          children: [
            SearchFilterBar(
              selected: _filter,
              onSelected: (filter) => setState(() => _filter = filter),
            ),
            Expanded(
              child: switch (sections) {
                null => loading,
                [] => message(
                  const ValueKey('search.noneOfType'),
                  'Rien de ce type pour « ${_query.trim()} ».',
                ),
                // Clé par recherche et par puce : on repart en haut.
                _ => SearchResults(
                  key: ValueKey((_query, _filter)),
                  sections: sections,
                  movies: _movies,
                  series: _series,
                  channels: _channels,
                ),
              },
            ),
          ],
        );
      } else if (!settled(channels)) {
        // Rien encore : les chaînes peuvent encore répondre.
        body = loading;
      } else if (moviesIndex == null && seriesIndex == null) {
        body = ErrorView(
          key: const ValueKey('search.error'),
          error: movies.error ?? series.error!,
          onRetry: () {
            ref.invalidate(catalogIndexProvider(ContentKind.movies));
            ref.invalidate(catalogIndexProvider(ContentKind.series));
          },
        );
      } else {
        body = message(
          const ValueKey('search.none'),
          'Aucun résultat pour « ${_query.trim()} ».',
        );
      }
    } else {
      body = loading;
    }

    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder(
          valueListenable: _controller,
          builder: (context, value, _) => TextEntry(
            key: const ValueKey('search.field'),
            controller: _controller,
            focusNode: widget.focusNode,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (text) {
              _timer?.cancel();
              _timer = Timer(_delay, () => _run(text));
            },
            onSubmitted: _run,
            decoration: InputDecoration(
              hintText: 'Rechercher un film, une série, une chaîne',
              prefixIcon: const Icon(Icons.search),
              border: InputBorder.none,
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('search.clear'),
                      tooltip: 'Effacer',
                      icon: const Icon(Icons.clear),
                      onPressed: _clear,
                    ),
            ),
          ),
        ),
        actions: const [SettingsButton()],
        // L'index se refait (filtre changé) : les résultats restent affichés.
        // Place gardée, pour que l'en-tête ne saute pas.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child:
              (movies.isLoading && movies.hasValue) ||
                  (series.isLoading && series.hasValue)
              ? const LinearProgressIndicator()
              : const SizedBox.shrink(),
        ),
      ),
      body: body,
    );
  }
}
