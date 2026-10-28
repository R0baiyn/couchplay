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
/// Chercher un titre passe par l'onglet Recherche.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key, required this.kind});

  final ContentKind kind;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String? _selectedId;
  var _refreshing = false;

  ContentKind get _kind => widget.kind;

  String get _title => _kind == ContentKind.movies ? 'Films' : 'Séries';

  /// Bouton de la catégorie sous le titre : 48 de haut, plus la marge.
  static const _pickerHeight = 56.0;

  static const _progress = PreferredSize(
    preferredSize: Size.fromHeight(4),
    child: LinearProgressIndicator(),
  );

  void _select(String id) => setState(() => _selectedId = id);

  /// Catégories, puis la liste complète du type, d'où viennent la grille, la
  /// recherche et les versions : deux requêtes. L'écran garde ses données
  /// (et la grille sa position) pendant le rechargement.
  Future<void> _refresh() async {
    // Tirer la grille pendant un rechargement ne le relance pas.
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(categoriesProvider(_kind).notifier).refresh();
      // Après les catégories : l'index, qui en dépend, ne se refait qu'une
      // fois avec les nouvelles.
      await ref.read(catalogIndexProvider(_kind).notifier).refresh();
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

  List<Widget> _actions(AsyncValue<Object?> categories) => [
    IconButton(
      tooltip: 'Actualiser',
      icon: const Icon(Icons.refresh),
      onPressed: categories.isLoading || _refreshing ? null : _refresh,
    ),
    const SettingsButton(),
  ];

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
    Widget plain(Widget body) => Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: _actions(categories),
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
                      onOpen: _open,
                      onRefresh: _refresh,
                    ),
                  ),
                ],
              ),
            );
          }
          // Écran étroit : titre, boutons et catégorie forment un en-tête
          // qui se replie quand on descend et revient dès qu'on remonte,
          // pour laisser la hauteur aux affiches. La catégorie se choisit
          // dans la liste complète, en panneau du bas.
          return Scaffold(
            body: _CategoryItems(
              key: key,
              kind: _kind,
              categoryId: current.id,
              onOpen: _open,
              onRefresh: _refresh,
              header: SliverAppBar(
                floating: true,
                snap: true,
                title: Text(_title),
                actions: _actions(categories),
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

/// Grille d'une catégorie, avec son éventuel en-tête repliable. La tirer
/// vers le bas l'actualise (toucher) ; « Actualiser » fait de même à la
/// souris et à la télécommande.
class _CategoryItems extends ConsumerWidget {
  const _CategoryItems({
    super.key,
    required this.kind,
    required this.categoryId,
    required this.onOpen,
    required this.onRefresh,
    this.header,
  });

  final ContentKind kind;
  final String categoryId;
  final ValueChanged<CatalogEntry> onOpen;
  final RefreshCallback onRefresh;

  /// En-tête qui défile avec la grille (écran étroit).
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(itemsProvider((kind, categoryId)));
    return FocusTraversalGroup(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
          // Une catégorie courte ou vide se tire aussi.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            ?header,
            ..._content(
              loaded,
              // Réessayer refait l'index : la grille en dépend.
              onRetry: () => ref.invalidate(catalogIndexProvider(kind)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(
    AsyncValue<Loaded<List<CatalogEntry>>?> loaded, {
    required VoidCallback onRetry,
  }) {
    Widget fill(Widget child) =>
        SliverFillRemaining(hasScrollBody: false, child: child);
    // La grille déjà là d'abord : pendant que l'index se refait
    // (« Actualiser », filtre changé), elle reste affichée.
    return switch (loaded) {
      AsyncValue(value: final value?) when value.value.isEmpty => [
        fill(const Center(child: Text('Cette catégorie est vide.'))),
      ],
      AsyncValue(value: final value?) => [
        if (value.offline)
          SliverToBoxAdapter(child: OfflineBanner(savedAt: value.savedAt)),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverPosterGrid(entries: value.value, onOpen: onOpen),
        ),
      ],

      AsyncError(:final error) when !loaded.isLoading => [
        fill(ErrorView(error: error, onRetry: onRetry)),
      ],
      // Chargement, ou catégorie pas encore dans l'index (valeur `null`).
      _ => [fill(const Center(child: CircularProgressIndicator()))],
    };
  }
}
