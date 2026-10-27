import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../server/models.dart';
import 'catalog_providers.dart';
import 'catalog_settings.dart';
import 'category_filter.dart';
import 'status_views.dart';

/// Réglages du catalogue du compte actif : pays affichés, contenu adulte, et
/// catégories une par une. Appliqués tout de suite aux onglets.
class CatalogSettingsScreen extends ConsumerWidget {
  const CatalogSettingsScreen({super.key});

  static const _tagNames = {
    'FR': 'France',
    'EN': 'Anglais',
    'ES': 'Espagnol',
    'IT': 'Italien',
    'DE': 'Allemand',
    'PT': 'Portugais',
    'AR': 'Arabe',
    'TR': 'Turc',
    'DZ': 'Algérie',
    'VOST': 'Version originale sous-titrée',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(catalogFilterProvider);
    final notifier = ref.read(catalogFilterProvider.notifier);
    final movies = ref.watch(categoriesProvider(ContentKind.movies));
    final series = ref.watch(categoriesProvider(ContentKind.series));

    final Widget body;
    if (movies case AsyncError(:final error)) {
      body = ErrorView(
        error: error,
        onRetry: () => ref.invalidate(categoriesProvider(ContentKind.movies)),
      );
    } else if (series case AsyncError(:final error)) {
      body = ErrorView(
        error: error,
        onRetry: () => ref.invalidate(categoriesProvider(ContentKind.series)),
      );
    } else if ((movies.value, series.value) case (final m?, final s?)) {
      final tags = detectTags([...m.value, ...s.value]);
      body = ListView(
        children: [
          SwitchListTile(
            autofocus: true,
            title: const Text('Afficher le contenu adulte'),
            value: filter.showAdult,
            onChanged: notifier.setShowAdult,
          ),
          const Divider(),
          ListTile(
            title: const Text('Pays et langues affichés'),
            subtitle: Text(
              filter.tags.isEmpty
                  ? 'Aucun coché : tout est affiché.'
                  : 'Les catégories sans pays restent toujours affichées.',
            ),
          ),
          for (final tag in tags)
            CheckboxListTile(
              title: Text(_tagNames[tag] ?? tag),
              subtitle: _tagNames.containsKey(tag) ? Text(tag) : null,
              value: filter.tags.contains(tag),
              onChanged: (shown) => notifier.setTag(tag, shown: shown ?? false),
            ),
          const Divider(),
          ListTile(
            title: const Text('Catégories une par une'),
            subtitle: const Text('Pour afficher ou masquer une catégorie'),
            trailing: filter.overrides.isEmpty
                ? null
                : TextButton(
                    onPressed: notifier.resetCategories,
                    child: const Text('Rétablir'),
                  ),
          ),
          _CategoryChoices(
            title: 'Films',
            kind: ContentKind.movies,
            categories: m.value,
            filter: filter,
          ),
          _CategoryChoices(
            title: 'Séries',
            kind: ContentKind.series,
            categories: s.value,
            filter: filter,
          ),
        ],
      );
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Catalogue')),
      body: body,
    );
  }
}

class _CategoryChoices extends ConsumerWidget {
  const _CategoryChoices({
    required this.title,
    required this.kind,
    required this.categories,
    required this.filter,
  });

  final String title;
  final ContentKind kind;
  final List<Category> categories;
  final CatalogFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = filter.apply(kind, categories).length;
    return ExpansionTile(
      title: Text(title),
      subtitle: Text('$visible affichées sur ${categories.length}'),
      children: [
        for (final category in categories)
          CheckboxListTile(
            dense: true,
            title: Text(category.name),
            value: filter.isVisible(kind, category),
            onChanged: (shown) => ref
                .read(catalogFilterProvider.notifier)
                .setCategory(kind, category, shown: shown ?? false),
          ),
      ],
    );
  }
}
