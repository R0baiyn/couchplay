import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../focus_ring.dart';
import '../focus_scroll.dart';
import '../server/models.dart';
import 'catalog_index.dart';
import 'versions.dart';
import 'catalog_repository.dart';
import 'poster_grid.dart';
import '../server/status_views.dart';

class CategoryList extends StatelessWidget {
  const CategoryList({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Category> categories;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SmoothFocusGroup(
      child: ListView.builder(
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          return ListTile(
            key: ValueKey('catalog.categoryTile.${category.id}'),
            title: FocusRing(child: Text(category.name)),
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
class CategoryItems extends ConsumerWidget {
  const CategoryItems({
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
    return SmoothFocusGroup(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
          key: const ValueKey('catalog.grid'),
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
        fill(
          const Center(
            child: Text(
              'Cette catégorie est vide.',
              key: ValueKey('catalog.empty'),
            ),
          ),
        ),
      ],
      AsyncValue(value: final value?) => [
        if (value.offline)
          SliverToBoxAdapter(
            child: OfflineBanner(
              key: const ValueKey('catalog.offlineBanner'),
              savedAt: value.savedAt,
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverPosterGrid(entries: value.value, onOpen: onOpen),
        ),
      ],
      AsyncError(:final error) when !loaded.isLoading => [
        fill(
          ErrorView(
            key: const ValueKey('catalog.error'),
            error: error,
            onRetry: onRetry,
          ),
        ),
      ],
      // Chargement, ou catégorie pas encore dans l'index (valeur `null`).
      _ => [fill(const Center(child: CircularProgressIndicator()))],
    };
  }
}
