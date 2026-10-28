import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../search/search_index.dart';
import '../server/models.dart';
import '../settings/settings_screen.dart';
import 'catalog_providers.dart';
import 'catalog_repository.dart';
import 'catalog_settings.dart';
import 'movie_screen.dart';
import 'poster_grid.dart';
import 'series_screen.dart';
import 'status_views.dart';
import 'versions.dart';

/// Ouvre la fiche d'un film ou d'une série.
void openDetails(BuildContext context, CatalogEntry entry) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => switch (entry.kind) {
      ContentKind.movies => MovieScreen(entry: entry),
      ContentKind.series => SeriesScreen(item: entry.item),
    },
  ),
);

/// Onglet Films ou Séries : catégories visibles, puis la grille de celle
/// choisie. Catégories en panneau latéral sur grand écran ; sur téléphone,
/// un bouton dans un en-tête qui se replie au défilement ouvre leur liste.
///
/// « Filtrer » réduit la grille aux titres qui contiennent les mots tapés,
/// dans la catégorie affichée seulement : une barre à droite de l'en-tête
/// sur grand écran ; sur téléphone, une loupe qui remplace le titre par la
/// barre.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key, required this.kind});

  final ContentKind kind;

  @override
  ConsumerState<CatalogScreen> createState() => CatalogScreenState();
}

class CatalogScreenState extends ConsumerState<CatalogScreen> {
  String? _selectedId;
  var _refreshing = false;
  final _filter = TextEditingController();
  final _filterFocus = FocusNode();

  /// Barre de filtre ouverte à la place du titre (écran étroit).
  var _filtering = false;

  /// Texte du filtre seul : bouger le curseur ne refiltre pas la grille.
  final _query = ValueNotifier('');

  @override
  void initState() {
    super.initState();
    _filter.addListener(() => _query.value = _filter.text);
  }

  ContentKind get _kind => widget.kind;

  String get _title => _kind == ContentKind.movies ? 'Films' : 'Séries';

  /// Bouton de la catégorie sous le titre : 48 de haut, plus la marge.
  static const _pickerHeight = 56.0;

  static const _progress = PreferredSize(
    preferredSize: Size.fromHeight(4),
    child: LinearProgressIndicator(),
  );

  @override
  void dispose() {
    _filter.dispose();
    _filterFocus.dispose();
    _query.dispose();
    super.dispose();
  }

  /// Ctrl+F (voir `HomeShell`) : ouvre la barre si besoin, curseur dedans.
  void focusFilter() {
    setState(() => _filtering = true);
    // Après la reconstruction : la barre vient peut-être d'apparaître.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _filterFocus.requestFocus();
    });
  }

  void _closeFilter() => setState(() {
    _filtering = false;
    _filter.clear();
  });

  /// Une autre catégorie repart sans filtre.
  void _select(String id) => setState(() {
    _selectedId = id;
    _filtering = false;
    _filter.clear();
  });

  /// Catégories et grille affichée ensemble, puis la liste complète de la
  /// recherche (un nouveau film y apparaît, et parmi les versions) ; l'écran
  /// garde ses données (et la grille sa position) pendant le rechargement.
  Future<void> _refresh(String? categoryId) async {
    setState(() => _refreshing = true);
    try {
      await Future.wait([
        ref.read(categoriesProvider(_kind).notifier).refresh(),
        if (categoryId != null)
          ref.read(itemsProvider((_kind, categoryId)).notifier).refresh(),
      ]);
      // Après les catégories : l'index, qui en dépend, ne se refait qu'une
      // fois avec les nouvelles.
      await ref.read(searchIndexProvider.notifier).refresh(_kind);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _open(CatalogEntry entry) => openDetails(context, entry);

  /// Liste complète des catégories sur écran étroit : un panneau du bas qui
  /// défile, reste au-dessus des boutons du téléphone, et se ferme sans rien
  /// changer si on touche à côté ou si on fait retour.
  Future<void> _pickCategory(
    List<Category> categories,
    String selectedId,
  ) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView.builder(
          controller: controller,
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 8,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            final current = category.id == selectedId;
            return ListTile(
              autofocus: current,
              selected: current,
              title: Text(category.name),
              trailing: current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, category.id),
            );
          },
        ),
      ),
    );
    if (id != null && id != selectedId && mounted) _select(id);
  }

  List<Widget> _actions(
    AsyncValue<Object?> categories,
    Category? selected, {
    Widget? filter,
  }) => [
    ?filter,
    IconButton(
      tooltip: 'Actualiser',
      icon: const Icon(Icons.refresh),
      onPressed: categories.isLoading || _refreshing
          ? null
          : () => _refresh(selected?.id),
    ),
    const SettingsButton(),
  ];

  /// Barre « Filtrer » : [leading] la ferme sur écran étroit, sinon une
  /// loupe ; la croix efface le texte.
  Widget _filterBar({Widget? leading}) => SearchBar(
    controller: _filter,
    focusNode: _filterFocus,
    hintText: 'Filtrer',
    textInputAction: TextInputAction.search,
    elevation: const WidgetStatePropertyAll(0),
    constraints: const BoxConstraints(minHeight: 40, maxHeight: 40),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
    leading: leading ?? const Icon(Icons.search),
    trailing: [
      ValueListenableBuilder(
        valueListenable: _query,
        builder: (context, text, _) => text.isEmpty
            ? const SizedBox.shrink()
            : IconButton(
                tooltip: 'Effacer',
                icon: const Icon(Icons.clear),
                onPressed: _filter.clear,
              ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider(_kind));
    final filter = ref.watch(catalogFilterProvider);
    final visible = switch (categories) {
      AsyncData(:final value) => filter.apply(_kind, value.value),
      _ => const <Category>[],
    };
    // Après un changement de compte ou de filtre, l'ancienne sélection peut
    // avoir disparu : la première catégorie visible la remplace.
    final selected =
        visible.where((c) => c.id == _selectedId).firstOrNull ??
        visible.firstOrNull;

    // Barre fixe classique, quand il n'y a pas de grille sous laquelle
    // replier l'en-tête (chargement, erreur, grand écran).
    // Sur grand écran, le filtre est une barre de largeur fixe, à droite,
    // près des boutons.
    Widget plain(Widget body, {bool withFilter = false}) => Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: _actions(
          categories,
          selected,
          filter: withFilter
              ? Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(width: 320, child: _filterBar()),
                )
              : null,
        ),
        bottom: _refreshing ? _progress : null,
      ),
      body: body,
    );

    return switch (categories) {
      AsyncValue(isLoading: true) => plain(
        const Center(child: CircularProgressIndicator()),
      ),
      AsyncError(:final error) => plain(
        ErrorView(
          error: error,
          onRetry: () => ref.invalidate(categoriesProvider(_kind)),
        ),
      ),
      AsyncData(:final value) when selected == null => plain(
        Column(
          children: [
            if (value.offline) OfflineBanner(savedAt: value.savedAt),
            const Expanded(
              child: Center(
                child: Text(
                  'Aucune catégorie à afficher.\n'
                  'Les pays affichés se choisissent dans les réglages.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
      AsyncData() => LayoutBuilder(
        builder: (context, constraints) {
          final current = selected!;
          // Clé par catégorie : une autre catégorie repart en haut.
          final key = ValueKey((_kind, current.id));
          // Panneau des catégories seulement sur grand écran : sur un
          // téléphone en paysage (~830 dp), il mangerait un tiers de la
          // largeur.
          if (constraints.maxWidth >= 1000) {
            return plain(
              Row(
                children: [
                  SizedBox(
                    width: 260,
                    child: _CategoryList(
                      categories: visible,
                      selectedId: current.id,
                      onSelect: _select,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _CategoryItems(
                      key: key,
                      kind: _kind,
                      categoryId: current.id,
                      query: _query,
                      onOpen: _open,
                    ),
                  ),
                ],
              ),
              withFilter: true,
            );
          }
          // Écran étroit : titre, boutons et catégorie forment un en-tête
          // qui se replie quand on descend et revient dès qu'on remonte,
          // pour laisser la hauteur aux affiches. La catégorie se choisit
          // dans la liste complète, en panneau du bas ; la loupe remplace le
          // titre et les boutons par la barre de filtre, sur toute la ligne.
          return Scaffold(
            body: _CategoryItems(
              key: key,
              kind: _kind,
              categoryId: current.id,
              query: _query,
              onOpen: _open,
              header: SliverAppBar(
                floating: true,
                snap: true,
                title: _filtering
                    ? _filterBar(
                        leading: IconButton(
                          tooltip: 'Fermer le filtre',
                          icon: const Icon(Icons.arrow_back),
                          onPressed: _closeFilter,
                        ),
                      )
                    : Text(_title),
                actions: _filtering
                    ? null
                    : [
                        IconButton(
                          tooltip: 'Filtrer',
                          icon: const Icon(Icons.search),
                          onPressed: focusFilter,
                        ),
                        ..._actions(categories, current),
                      ],
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(
                    _pickerHeight + (_refreshing ? 4 : 0),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            alignment: Alignment.centerLeft,
                          ),
                          icon: const Icon(Icons.arrow_drop_down),
                          label: Text(
                            current.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () => _pickCategory(visible, current.id),
                        ),
                      ),
                      if (_refreshing) _progress,
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
      _ => plain(const SizedBox.shrink()),
    };
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Category> categories;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      child: ListView.builder(
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          return ListTile(
            title: Text(category.name),
            selected: category.id == selectedId,
            onTap: () => onSelect(category.id),
          );
        },
      ),
    );
  }
}

/// Grille d'une catégorie, réduite par le texte de [query], avec son
/// éventuel en-tête repliable.
class _CategoryItems extends ConsumerWidget {
  const _CategoryItems({
    super.key,
    required this.kind,
    required this.categoryId,
    required this.query,
    required this.onOpen,
    this.header,
  });

  final ContentKind kind;
  final String categoryId;
  final ValueListenable<String> query;

  final ValueChanged<CatalogEntry> onOpen;

  /// En-tête qui défile avec la grille (écran étroit).
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = itemsProvider((kind, categoryId));
    final loaded = ref.watch(provider);
    // Seules les affiches suivent la frappe ; l'en-tête, et le champ qu'il
    // contient, restent les mêmes widgets.
    return FocusTraversalGroup(
      child: ValueListenableBuilder(
        valueListenable: query,
        builder: (context, text, _) => CustomScrollView(
          slivers: [
            ?header,
            ..._content(loaded, text, onRetry: () => ref.invalidate(provider)),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(
    AsyncValue<Loaded<List<CatalogEntry>>> loaded,
    String query, {
    required VoidCallback onRetry,
  }) {
    Widget fill(Widget child) =>
        SliverFillRemaining(hasScrollBody: false, child: child);
    return switch (loaded) {
      AsyncValue(isLoading: true) => [
        fill(const Center(child: CircularProgressIndicator())),
      ],
      AsyncError(:final error) => [
        fill(ErrorView(error: error, onRetry: onRetry)),
      ],
      AsyncData(:final value) when value.value.isEmpty => [
        fill(const Center(child: Text('Cette catégorie est vide.'))),
      ],
      AsyncData(:final value) => switch (search(value.value, query)) {
        final entries when entries.isEmpty => [
          fill(
            Center(
              child: Text(
                'Rien ne correspond à « ${query.trim()} » '
                'dans cette catégorie.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
        final entries => [
          if (value.offline)
            SliverToBoxAdapter(child: OfflineBanner(savedAt: value.savedAt)),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverPosterGrid(entries: entries, onOpen: onOpen),
          ),
        ],
      },
      _ => const <Widget>[],
    };
  }
}
