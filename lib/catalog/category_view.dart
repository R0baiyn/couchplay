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
    required this.tileKey,
  });

  final List<Category> categories;
  final String selectedId;
  final ValueChanged<String> onSelect;

  /// Key d'une ligne, donnée par l'écran (D-048).
  final Key Function(String id) tileKey;

  @override
  Widget build(BuildContext context) {
    return SmoothFocusGroup(
      child: ListView.builder(
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          return ListTile(
            key: tileKey(category.id),
            title: FocusRing(child: Text(category.name)),
            selected: category.id == selectedId,
            onTap: () => onSelect(category.id),
          );
        },
      ),
    );
  }
}

/// Barre de progression d'« Actualiser », sous l'en-tête.
const refreshProgress = PreferredSize(
  preferredSize: Size.fromHeight(4),
  child: LinearProgressIndicator(),
);

/// En-tête d'un écran étroit : titre, boutons et bouton de la catégorie, qui
/// se replient quand on descend et reviennent dès qu'on remonte.
class CategoryHeader extends StatelessWidget {
  const CategoryHeader({
    super.key,
    required this.title,
    required this.actions,
    required this.category,
    required this.refreshing,
    required this.pickerKey,
    required this.onPick,
  });

  final String title;
  final List<Widget> actions;

  /// Catégorie affichée.
  final Category category;
  final bool refreshing;
  final Key pickerKey;
  final VoidCallback onPick;

  /// Bouton de la catégorie sous le titre : 48 de haut, plus la marge.
  static const _pickerHeight = 56.0;

  @override
  Widget build(BuildContext context) => SliverAppBar(
    floating: true,
    snap: true,
    title: Text(title),
    actions: actions,
    bottom: PreferredSize(
      preferredSize: Size.fromHeight(_pickerHeight + (refreshing ? 4 : 0)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OutlinedButton.icon(
              key: pickerKey,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                alignment: Alignment.centerLeft,
              ),
              icon: const Icon(Icons.arrow_drop_down),
              label: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: onPick,
            ),
          ),
          if (refreshing) refreshProgress,
        ],
      ),
    ),
  );
}

/// Liste complète des catégories sur écran étroit : un panneau du bas qui
/// défile, reste au-dessus des boutons du téléphone, et se ferme sans rien
/// changer (`null`) si on touche à côté ou si on fait retour.
Future<String?> pickCategory(
  BuildContext context, {
  required List<Category> categories,
  required String selectedId,
  required Key Function(String id) tileKey,
}) => showModalBottomSheet<String>(
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
          key: tileKey(category.id),
          autofocus: current,
          selected: current,
          title: FocusRing(child: Text(category.name)),
          trailing: current ? const Icon(Icons.check) : null,
          onTap: () => Navigator.pop(context, category.id),
        );
      },
    ),
  ),
);

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
