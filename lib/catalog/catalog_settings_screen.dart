import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../focus_ring.dart';
import '../server/models.dart';
import 'catalog_providers.dart';
import 'catalog_settings.dart';
import 'category_filter.dart';
import '../server/status_views.dart';

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
        key: const ValueKey('catalog.settingsError'),
        error: error,
        onRetry: () => ref.invalidate(categoriesProvider(ContentKind.movies)),
      );
    } else if (series case AsyncError(:final error)) {
      body = ErrorView(
        key: const ValueKey('catalog.settingsError'),
        error: error,
        onRetry: () => ref.invalidate(categoriesProvider(ContentKind.series)),
      );
    } else if ((movies.value, series.value) case (final m?, final s?)) {
      final tags = detectTags([...m.value, ...s.value]);
      // Slivers : les catégories, des centaines, ne sont construites qu'en
      // défilant.
      body = CustomScrollView(
        slivers: [
          SliverList.list(
            children: [
              SwitchListTile(
                key: const ValueKey('catalog.adultSwitch'),
                autofocus: true,
                title: const FocusRing(
                  child: Text('Afficher le contenu adulte'),
                ),
                value: filter.showAdult,
                onChanged: notifier.setShowAdult,
              ),
              const Divider(),
              ListTile(
                title: const FocusRing(child: Text('Pays et langues affichés')),
                subtitle: Text(
                  filter.tags.isEmpty
                      ? 'Aucun coché : tout est affiché.'
                      : 'Les catégories sans pays restent toujours affichées.',
                ),
              ),
              for (final tag in tags)
                CheckboxListTile(
                  key: ValueKey('catalog.tag.$tag'),
                  title: FocusRing(child: Text(_tagNames[tag] ?? tag)),
                  subtitle: _tagNames.containsKey(tag) ? Text(tag) : null,
                  value: filter.tags.contains(tag),
                  onChanged: (shown) =>
                      notifier.setTag(tag, shown: shown ?? false),
                ),
              const Divider(),
              ListTile(
                title: const FocusRing(child: Text('Catégories une par une')),
                subtitle: const Text('Pour afficher ou masquer une catégorie'),
                trailing: filter.overrides.isEmpty
                    ? null
                    : TextButton(
                        key: const ValueKey('catalog.resetCategories'),
                        onPressed: notifier.resetCategories,
                        child: const Text('Rétablir'),
                      ),
              ),
            ],
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

/// Un type de contenu, repliable, et ses catégories en dessous une fois
/// déplié : en sliver paresseux plutôt que dans l'`ExpansionTile`, qui les
/// construirait toutes d'un coup. Mêmes bordures qu'un `ExpansionTile`
/// déplié : un trait au-dessus de l'en-tête, un sous la dernière catégorie.
class _CategoryChoices extends ConsumerStatefulWidget {
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
  ConsumerState<_CategoryChoices> createState() => _CategoryChoicesState();
}

class _CategoryChoicesState extends ConsumerState<_CategoryChoices> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final categories = widget.categories;
    final filter = widget.filter;
    final visible = filter.apply(kind, categories).length;
    final divider = BorderSide(color: Theme.of(context).dividerColor);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: ExpansionTile(
            key: ValueKey('catalog.kindTile.${kind.name}'),
            title: FocusRing(child: Text(widget.title)),
            subtitle: Text('$visible affichées sur ${categories.length}'),
            shape: Border(top: divider),
            onExpansionChanged: (expanded) =>
                setState(() => _expanded = expanded),
          ),
        ),
        if (_expanded)
          SliverList.builder(
            itemCount: categories.length,
            itemBuilder: (context, i) {
              final category = categories[i];
              final tile = CheckboxListTile(
                key: ValueKey(
                  'catalog.categoryCheck.${kind.name}.${category.id}',
                ),
                dense: true,
                title: FocusRing(child: Text(category.name)),
                value: filter.isVisible(kind, category),
                onChanged: (shown) => ref
                    .read(catalogFilterProvider.notifier)
                    .setCategory(kind, category, shown: shown ?? false),
              );
              return i < categories.length - 1
                  ? tile
                  : DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        border: Border(bottom: divider),
                      ),
                      child: tile,
                    );
            },
          ),
      ],
    );
  }
}
