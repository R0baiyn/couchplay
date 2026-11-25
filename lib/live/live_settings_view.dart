import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_settings.dart';
import '../catalog/catalog_settings_screen.dart';
import '../server/status_views.dart';
import 'live_providers.dart';

/// Section « Chaînes » des réglages du catalogue : mêmes cases que Films et
/// Séries. Un sliver, avec son propre chargement et sa propre erreur : les
/// chaînes ne retiennent pas le reste de l'écran.
class LiveCategorySettings extends ConsumerWidget {
  const LiveCategorySettings({super.key});

  static const _title = 'Chaînes';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(catalogFilterProvider);
    return switch (ref.watch(liveCatalogProvider)) {
      AsyncValue(value: final loaded?) => CategoryChoices(
        title: _title,
        categories: loaded.value.categories,
        isVisible: filter.isLiveVisible,
        onChanged: (category, shown) => ref
            .read(catalogFilterProvider.notifier)
            .setLiveCategory(category, shown: shown),
        tileKey: const ValueKey('live.settingsTile'),
        checkKey: (id) => ValueKey('live.categoryCheck.$id'),
      ),
      AsyncError(:final error, isLoading: false) => SliverToBoxAdapter(
        child: ErrorView(
          key: const ValueKey('live.settingsError'),
          error: error,
          onRetry: () => ref.invalidate(liveCatalogProvider),
        ),
      ),
      _ => const SliverToBoxAdapter(
        child: ListTile(title: Text(_title), subtitle: Text('Chargement…')),
      ),
    };
  }
}
