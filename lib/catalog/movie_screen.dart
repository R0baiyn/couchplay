import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../server/models.dart';
import 'catalog_providers.dart';
import 'details_view.dart';
import 'status_views.dart';

/// Fiche d'un film. Le bouton « Lecture » arrive à l'étape 4.
class MovieScreen extends ConsumerWidget {
  const MovieScreen({super.key, required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = movieDetailsProvider(item.id);
    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: switch (ref.watch(provider)) {
        AsyncData(:final value) => SingleChildScrollView(
          child: DetailsHeader(details: value.details),
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
