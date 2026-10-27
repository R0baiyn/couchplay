import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_providers.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/catalog_settings.dart';
import '../catalog/versions.dart';
import '../server/item_name.dart';
import '../server/models.dart';

/// Films ou séries des catégories visibles, en affiches, avec l'affiche de
/// chaque entrée du serveur : la fiche d'un film y retrouve ses versions.
final class KindIndex {
  KindIndex(this.entries)
    : _byId = {
        for (final entry in entries)
          for (final version in entry.versions) version.id: entry,
      };

  final List<CatalogEntry> entries;
  final Map<String, CatalogEntry> _byId;

  /// Affiche qui contient l'entrée [id], `null` si sa catégorie est masquée.
  CatalogEntry? entryOf(String id) => _byId[id];
}

/// Tout le catalogue visible du compte, pour la recherche et les versions.
final class SearchIndex {
  const SearchIndex({required this.movies, required this.series});

  final KindIndex movies;
  final KindIndex series;
}

/// Décodeur de la liste complète d'un type, pour [CatalogRepository.all] :
/// garde les entrées des catégories [visible] et regroupe les versions,
/// le tout dans l'isolate. Ne capture que ses paramètres, donc peut y partir.
KindIndex Function(String) indexParser(ContentKind kind, Set<String> visible) =>
    (text) => KindIndex(
      entriesOf(
        parseCatalogItems(
          text,
          kind,
        ).where((item) => visible.contains(item.categoryId)),
      ),
    );

/// Mots d'une recherche, normalisés comme les titres ([normalize]).
List<String> queryWords(String query) => [
  for (final word in normalize(query).split(' '))
    if (word.isNotEmpty) word,
];

/// Affiches dont un titre (de n'importe quelle version) contient chaque mot
/// de [query], dans l'ordre de [entries] ; celles dont le titre commence par
/// la recherche passent devant. Une recherche vide garde tout.
List<CatalogEntry> search(List<CatalogEntry> entries, String query) {
  final words = queryWords(query);
  if (words.isEmpty) return entries;
  final start = words.join(' ');
  final first = <CatalogEntry>[];
  final rest = <CatalogEntry>[];
  for (final entry in entries) {
    var matches = false;
    var starts = false;
    for (final version in entry.versions) {
      final text = version.parsedName.text;
      if (words.every(text.contains)) {
        matches = true;
        if (text.startsWith(start)) {
          starts = true;
          break;
        }
      }
    }
    if (matches) (starts ? first : rest).add(entry);
  }
  return [...first, ...rest];
}

/// Index du compte actif. Chargé en arrière-plan dès l'accueil affiché
/// (voir `HomeShell`), puis gardé tant que l'accueil existe ; refait au
/// changement de compte, de filtre ou de catégories. Le refaire relit le
/// cache disque, sans appel au serveur pendant 24 h, sauf « Actualiser »
/// ([SearchIndexNotifier.refresh]).
final searchIndexProvider =
    AsyncNotifierProvider.autoDispose<SearchIndexNotifier, SearchIndex>(
      SearchIndexNotifier.new,
      retry: noRetry,
    );

class SearchIndexNotifier extends AsyncNotifier<SearchIndex> {
  /// Types à redemander au serveur au prochain calcul, même si le cache est
  /// récent.
  final _stale = <ContentKind>{};

  @override
  Future<SearchIndex> build() async {
    final repository = ref.watch(catalogRepositoryProvider);
    final filter = ref.watch(catalogFilterProvider);
    final movieCategories = ref.watch(
      categoriesProvider(ContentKind.movies).future,
    );
    final seriesCategories = ref.watch(
      categoriesProvider(ContentKind.series).future,
    );
    final stale = {..._stale};
    _stale.clear();

    Future<KindIndex> load(
      ContentKind kind,
      Future<Loaded<List<Category>>> categories,
    ) async {
      final visible = {
        for (final category in filter.apply(kind, (await categories).value))
          category.id,
      };
      return (await repository.all(
        kind,
        indexParser(kind, visible),
        refresh: stale.contains(kind),
      )).value;
    }

    final [movies, series] = await Future.wait([
      load(ContentKind.movies, movieCategories),
      load(ContentKind.series, seriesCategories),
    ]);
    return SearchIndex(movies: movies, series: series);
  }

  /// « Actualiser » : redemande au serveur la liste complète de [kind]
  /// (l'autre type relit son cache). Les résultats affichés restent en place
  /// pendant le chargement. Une erreur est gardée dans l'état, pour l'onglet
  /// Recherche, sans être relancée ici.
  Future<void> refresh(ContentKind kind) async {
    _stale.add(kind);
    ref.invalidateSelf();
    try {
      await future;
    } on Object {
      // L'onglet Recherche affiche l'erreur et propose « Réessayer ».
    }
  }
}
