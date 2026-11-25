import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'catalog_index.dart';
import '../server/models.dart';
import '../library/library.dart';
import 'catalog_providers.dart';
import 'catalog_settings.dart';
import 'movie_screen.dart';
import 'category_view.dart';
import 'series_screen.dart';
import '../server/status_views.dart';
import 'versions.dart';

/// Ouvre la fiche d'un film ou d'une série. [episode] : pour une série, la
/// fiche s'ouvre sur cet épisode (saison choisie, page défilée, focus).
void openDetails(
  BuildContext context,
  CatalogEntry entry, {
  PlayItem? episode,
}) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => switch (entry.kind) {
      ContentKind.movies => MovieScreen(entry: entry),
      ContentKind.series => SeriesScreen(item: entry.item, episode: episode),
    },
  ),
);

/// Onglet Films ou Séries : catégories visibles, puis la grille de celle
/// choisie. Catégories en panneau latéral sur grand écran ; sur téléphone,
/// un bouton dans un en-tête qui se replie au défilement ouvre leur liste.
/// Chercher un titre passe par l'onglet Recherche.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key, required this.kind, this.headerActions});

  final ContentKind kind;

  /// Boutons de fin d'en-tête posés par la coquille : les réglages sont
  /// au-dessus du catalogue (D-050).
  final Widget? headerActions;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String? _selectedId;
  var _refreshing = false;

  ContentKind get _kind => widget.kind;

  String get _title => _kind == ContentKind.movies ? 'Films' : 'Séries';

  void _select(String id) => setState(() => _selectedId = id);

  /// Catégories, puis la liste complète du type, d'où viennent la grille, la
  /// recherche et les versions : deux requêtes. L'écran garde ses données
  /// (et la grille sa position) pendant le rechargement.
  Future<void> _refresh() async {
    // Tirer la grille pendant un rechargement ne le relance pas.
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      // Catégories d'abord, puis l'index, refait une fois avec elles.
      await ref.read(catalogIndexProvider(_kind).notifier).refresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _open(CatalogEntry entry) => openDetails(context, entry);

  Future<void> _pickCategory(
    List<Category> categories,
    String selectedId,
  ) async {
    final id = await pickCategory(
      context,
      categories: categories,
      selectedId: selectedId,
      tileKey: (id) => ValueKey('catalog.categorySheetTile.$id'),
    );
    if (id != null && id != selectedId && mounted) _select(id);
  }

  List<Widget> _actions(AsyncValue<Object?> categories) => [
    IconButton(
      key: const ValueKey('catalog.refresh'),
      tooltip: 'Actualiser',
      icon: const Icon(Icons.refresh),
      onPressed: categories.isLoading || _refreshing ? null : _refresh,
    ),
    ?widget.headerActions,
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
        bottom: _refreshing ? refreshProgress : null,
      ),
      body: body,
    );

    return switch (categories) {
      AsyncValue(isLoading: true) => plain(
        const Center(child: CircularProgressIndicator()),
      ),
      AsyncError(:final error) => plain(
        ErrorView(
          key: const ValueKey('catalog.error'),
          error: error,
          onRetry: () => ref.invalidate(categoriesProvider(_kind)),
        ),
      ),
      AsyncData(:final value) when selected == null => plain(
        Column(
          children: [
            if (value.offline)
              OfflineBanner(
                key: const ValueKey('catalog.offlineBanner'),
                savedAt: value.savedAt,
              ),
            const Expanded(
              child: Center(
                child: Text(
                  key: ValueKey('catalog.noCategory'),
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
                    child: CategoryList(
                      categories: visible,
                      selectedId: current.id,
                      onSelect: _select,
                      tileKey: (id) => ValueKey('catalog.categoryTile.$id'),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: CategoryItems(
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
            body: CategoryItems(
              key: key,
              kind: _kind,
              categoryId: current.id,
              onOpen: _open,
              onRefresh: _refresh,
              header: CategoryHeader(
                title: _title,
                actions: _actions(categories),
                category: current,
                refreshing: _refreshing,
                pickerKey: const ValueKey('catalog.categoryPicker'),
                onPick: () => _pickCategory(visible, current.id),
              ),
            ),
          );
        },
      ),
      _ => plain(const SizedBox.shrink()),
    };
  }
}
