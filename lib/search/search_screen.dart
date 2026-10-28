import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_screen.dart';
import '../catalog/poster_grid.dart';
import '../catalog/status_views.dart';
import '../catalog/versions.dart';
import '../server/models.dart';
import '../settings/settings_screen.dart';
import 'search_index.dart';

/// Onglet Recherche : tout le catalogue visible, films puis séries.
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

  // Derniers résultats, refaits seulement si un index ou la recherche change.
  KindIndex? _moviesIndex;
  KindIndex? _seriesIndex;
  String? _searched;
  var _movies = const <CatalogEntry>[];
  var _series = const <CatalogEntry>[];

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
    final words = queryWords(_query);
    // Fini : chargé, ou en échec sans rien à montrer.
    bool settled(AsyncValue<Object?> index) =>
        index.hasValue || (index.hasError && !index.isLoading);
    final theme = Theme.of(context);

    Widget message(String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );

    final Widget body;
    if (words.isEmpty) {
      body = message('Tape quelques lettres d\'un film ou d\'une série.');
    } else if (settled(movies) && settled(series)) {
      // Un type en échec n'empêche pas de chercher dans l'autre.
      final moviesIndex = movies.value?.value;
      final seriesIndex = series.value?.value;
      if (moviesIndex == null && seriesIndex == null) {
        body = ErrorView(
          error: movies.error ?? series.error!,
          onRetry: () {
            ref.invalidate(catalogIndexProvider(ContentKind.movies));
            ref.invalidate(catalogIndexProvider(ContentKind.series));
          },
        );
      } else {
        if (!identical(moviesIndex, _moviesIndex) ||
            !identical(seriesIndex, _seriesIndex) ||
            _query != _searched) {
          _moviesIndex = moviesIndex;
          _seriesIndex = seriesIndex;
          _searched = _query;
          _movies = search(moviesIndex?.entries ?? const [], _query);
          _series = search(seriesIndex?.entries ?? const [], _query);
        }
        body = _movies.isEmpty && _series.isEmpty
            ? message('Aucun résultat pour « ${_query.trim()} ».')
            // Clé par recherche : une nouvelle recherche repart en haut.
            : _Results(key: ValueKey(_query), movies: _movies, series: _series);
      }
    } else {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            const CircularProgressIndicator(),
            Text('Chargement du catalogue…', style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder(
          valueListenable: _controller,
          builder: (context, value, _) => TextField(
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
              hintText: 'Rechercher un film, une série',
              prefixIcon: const Icon(Icons.search),
              border: InputBorder.none,
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
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

/// Résultats en deux sections, Films puis Séries, dans une seule liste qui
/// défile ; les affiches ne sont construites qu'à l'écran.
class _Results extends StatelessWidget {
  const _Results({super.key, required this.movies, required this.series});

  final List<CatalogEntry> movies;
  final List<CatalogEntry> series;

  @override
  Widget build(BuildContext context) {
    void open(CatalogEntry entry) => openDetails(context, entry);
    Widget section(String title, List<CatalogEntry> entries) =>
        SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  '$title (${entries.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverPosterGrid(entries: entries, onOpen: open),
            ),
          ],
        );
    return FocusTraversalGroup(
      child: CustomScrollView(
        slivers: [
          if (movies.isNotEmpty) section('Films', movies),
          if (series.isNotEmpty) section('Séries', series),
        ],
      ),
    );
  }
}
