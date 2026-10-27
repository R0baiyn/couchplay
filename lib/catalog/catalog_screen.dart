import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../server/models.dart';
import 'catalog_providers.dart';
import 'catalog_settings.dart';
import 'movie_screen.dart';
import 'poster_grid.dart';
import 'series_screen.dart';
import 'status_views.dart';

/// Onglet Films ou Séries : catégories visibles, puis la grille de celle
/// choisie. Catégories en panneau latéral sur grand écran, en menu sur mobile.
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

  /// Catégories et grille affichée ensemble ; l'écran garde ses données (et
  /// la grille sa position) pendant le rechargement.
  Future<void> _refresh(String? categoryId) async {
    setState(() => _refreshing = true);
    try {
      await Future.wait([
        ref.read(categoriesProvider(_kind).notifier).refresh(),
        if (categoryId != null)
          ref.read(itemsProvider((_kind, categoryId)).notifier).refresh(),
      ]);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _open(CatalogItem item) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => switch (item.kind) {
        ContentKind.movies => MovieScreen(item: item),
        ContentKind.series => SeriesScreen(item: item),
      },
    ),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_kind == ContentKind.movies ? 'Films' : 'Séries'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: categories.isLoading || _refreshing
                ? null
                : () => _refresh(selected?.id),
          ),
        ],
        bottom: _refreshing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: switch (categories) {
        AsyncValue(isLoading: true) => const Center(
          child: CircularProgressIndicator(),
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(categoriesProvider(_kind)),
        ),
        AsyncData(:final value) when selected == null => Column(
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
        AsyncData() => LayoutBuilder(
          builder: (context, constraints) {
            // Le bandeau hors ligne est affiché par la grille, une seule fois.
            final items = _CategoryItems(
              key: ValueKey((_kind, selected!.id)),
              kind: _kind,
              categoryId: selected.id,
              onOpen: _open,
            );
            void select(String? id) => setState(() => _selectedId = id);
            if (constraints.maxWidth >= 720) {
              return Row(
                children: [
                  SizedBox(
                    width: 260,
                    child: _CategoryList(
                      categories: visible,
                      selectedId: selected.id,
                      onSelect: select,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: items),
                ],
              );
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: DropdownMenu<String>(
                    // Recréé seulement quand la liste change (compte,
                    // filtre) : un choix au clavier garde ainsi le focus.
                    key: ValueKey(Object.hashAll(visible.map((c) => c.id))),
                    initialSelection: selected.id,
                    expandedInsets: EdgeInsets.zero,
                    label: const Text('Catégorie'),
                    onSelected: select,
                    dropdownMenuEntries: [
                      for (final c in visible)
                        DropdownMenuEntry(value: c.id, label: c.name),
                    ],
                  ),
                ),
                Expanded(child: items),
              ],
            );
          },
        ),
        _ => const SizedBox.shrink(),
      },
    );
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

class _CategoryItems extends ConsumerWidget {
  const _CategoryItems({
    super.key,
    required this.kind,
    required this.categoryId,
    required this.onOpen,
  });

  final ContentKind kind;
  final String categoryId;
  final ValueChanged<CatalogItem> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = itemsProvider((kind, categoryId));
    return switch (ref.watch(provider)) {
      AsyncValue(isLoading: true) => const Center(
        child: CircularProgressIndicator(),
      ),
      AsyncError(:final error) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(provider),
      ),
      AsyncData(:final value) when value.value.isEmpty => const Center(
        child: Text('Cette catégorie est vide.'),
      ),
      AsyncData(:final value) => Column(
        children: [
          if (value.offline) OfflineBanner(savedAt: value.savedAt),
          Expanded(
            child: PosterGrid(items: value.value, onOpen: onOpen),
          ),
        ],
      ),
      _ => const SizedBox.shrink(),
    };
  }
}
