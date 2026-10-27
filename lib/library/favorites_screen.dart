import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_screen.dart';
import '../catalog/poster_grid.dart';
import '../server/models.dart';
import 'library_store.dart';

/// « Tout voir » : tous les favoris en grille, filtrables Films / Séries.
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  /// `null` : tout.
  ContentKind? _kind;

  @override
  Widget build(BuildContext context) {
    // Les favoris seuls : la progression enregistrée pendant la lecture ne
    // reconstruit pas la grille.
    ref.watch(libraryProvider.select((l) => l.favorites));
    final favorites = ref.read(libraryProvider).favoritesByDate;
    final items = [
      for (final favorite in favorites)
        if (_kind == null || favorite.item.kind == _kind) favorite.item,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Ma liste')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SegmentedButton<ContentKind?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('Tout')),
                  ButtonSegment(
                    value: ContentKind.movies,
                    label: Text('Films'),
                  ),
                  ButtonSegment(
                    value: ContentKind.series,
                    label: Text('Séries'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (kinds) =>
                    setState(() => _kind = kinds.first),
              ),
            ),
          ),
          if (items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('Rien dans ma liste ici.')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverPosterGrid(
                items: items,
                onOpen: (item) => openDetails(context, item),
              ),
            ),
        ],
      ),
    );
  }
}
