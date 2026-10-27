import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_store.dart';

/// Cœur « Ajouter à ma liste » / « Retirer de ma liste » des fiches.
///
/// Pour un film en plusieurs versions, le cœur est plein si l'une d'elles
/// est dans la liste : le retirer les retire toutes, l'ajouter ajoute celle
/// affichée. Le même film n'apparaît donc pas deux fois dans « Ma liste ».
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({
    super.key,
    required this.favoriteKey,
    required this.name,
    this.poster,
    this.otherKeys = const [],
  });

  /// `movie:<id>` ou `series:<id>`.
  final String favoriteKey;
  final String name;
  final String? poster;

  /// Clés des autres versions du même film.
  final List<String> otherKeys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = [favoriteKey, ...otherKeys];
    final favorite = ref.watch(
      libraryProvider.select((l) => keys.any(l.favorites.containsKey)),
    );
    final library = ref.read(libraryProvider.notifier);
    return IconButton(
      tooltip: favorite ? 'Retirer de ma liste' : 'Ajouter à ma liste',
      icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
      onPressed: () => favorite
          ? library.removeFavorites(keys)
          : library.toggleFavorite(
              key: favoriteKey,
              name: name,
              poster: poster,
            ),
    );
  }
}
