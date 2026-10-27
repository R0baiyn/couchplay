import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/favorite_button.dart';
import '../library/library.dart';
import '../player/player_screen.dart';
import '../server/models.dart';
import 'catalog_providers.dart';
import 'details_view.dart';
import 'status_views.dart';

/// Fiche d'un film, avec le bouton « Lecture ».
class MovieScreen extends ConsumerWidget {
  const MovieScreen({super.key, required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = movieDetailsProvider(item.id);
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          FavoriteButton(
            favoriteKey: 'movie:${item.id}',
            name: item.name,
            poster: item.poster,
          ),
        ],
      ),
      body: switch (ref.watch(provider)) {
        AsyncData(:final value) => SingleChildScrollView(
          child: DetailsHeader(
            details: value.details,
            action: _PlayButton(
              item: item,
              extension: value.extension ?? item.extension,
            ),
          ),
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(provider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _PlayButton extends ConsumerWidget {
  const _PlayButton({required this.item, required this.extension});

  final CatalogItem item;
  final String? extension;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extension = this.extension;
    return FilledButton.icon(
      autofocus: true,
      icon: const Icon(Icons.play_arrow),
      label: Text(extension == null ? 'Fichier introuvable' : 'Lecture'),
      onPressed: extension == null
          ? null
          : () => openPlayer(
              context,
              ref,
              PlayItem.movie(
                id: item.id,
                extension: extension,
                name: item.name,
                poster: item.poster,
              ),
            ),
    );
  }
}
