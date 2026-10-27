import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_screen.dart';
import '../catalog/poster_grid.dart';
import '../settings/settings_screen.dart';
import 'favorites_screen.dart';
import 'library_store.dart';

/// Premier onglet : « Ma liste » en rangée, la plus récente en premier.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _tileWidth = 130.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(
      libraryProvider.select((l) => l.favoritesByDate),
    );
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accueil'),
        actions: const [SettingsButton()],
      ),
      body: favorites.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ma liste est vide.\n'
                  'Le cœur d\'une fiche de film ou de série l\'y ajoute.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Ma liste',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const FavoritesScreen(),
                          ),
                        ),
                        child: const Text('Tout voir'),
                      ),
                    ],
                  ),
                ),
                // Rangée glissable aussi à la souris ; Shift + molette et les
                // flèches la font défiler d'office. Construite en entier :
                // une liste de favoris reste courte.
                ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: SliverPosterGrid.spacing,
                      children: [
                        for (final favorite in favorites)
                          SizedBox(
                            width: _tileWidth,
                            child: PosterTile(
                              key: ValueKey(favorite.key),
                              title: favorite.name,
                              imageUrl: favorite.poster,
                              onTap: () => openDetails(context, favorite.item),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
