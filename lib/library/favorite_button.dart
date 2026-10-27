import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_store.dart';

/// Cœur « Ajouter à ma liste » / « Retirer de ma liste » des fiches.
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({
    super.key,
    required this.favoriteKey,
    required this.name,
    this.poster,
  });

  /// `movie:<id>` ou `series:<id>`.
  final String favoriteKey;
  final String name;
  final String? poster;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorite = ref.watch(
      libraryProvider.select((l) => l.favorites.containsKey(favoriteKey)),
    );
    return IconButton(
      tooltip: favorite ? 'Retirer de ma liste' : 'Ajouter à ma liste',
      icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
      onPressed: () => ref
          .read(libraryProvider.notifier)
          .toggleFavorite(key: favoriteKey, name: name, poster: poster),
    );
  }
}
