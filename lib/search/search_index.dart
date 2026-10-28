import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_providers.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/catalog_settings.dart';
import '../catalog/versions.dart';
import '../server/item_name.dart';
import '../server/models.dart';

/// Films ou séries des catégories visibles, tirés de la liste complète :
/// les affiches de tout le catalogue (recherche), celles de chaque catégorie
/// (grilles), et pour chaque entrée du serveur l'affiche qui la contient (la
/// fiche d'un film y retrouve ses versions).
final class KindIndex {
  KindIndex(this.entries, this._byCategory, this._categories)
    : _byId = {
        for (final entry in entries)
          for (final version in entry.versions) version.id: entry,
      };

  final List<CatalogEntry> entries;
  final Map<String, List<CatalogEntry>> _byCategory;

  /// Catégories visibles quand l'index a été fait.
  final Set<String> _categories;
  final Map<String, CatalogEntry> _byId;

  /// Affiche qui contient l'entrée [id], `null` si sa catégorie est masquée.
  CatalogEntry? entryOf(String id) => _byId[id];

  /// Affiches d'une catégorie, versions regroupées dans la seule catégorie ;
  /// vide si le serveur n'y a rien. `null` si l'index ne la couvre pas
  /// (masquée quand il a été fait).
  List<CatalogEntry>? entriesIn(String categoryId) =>
      _byCategory[categoryId] ??
      (_categories.contains(categoryId) ? const [] : null);
}

/// Décodeur de la liste complète d'un type, pour [CatalogRepository.all] :
/// garde les entrées des catégories [visible], les range par catégorie et
/// regroupe les versions, le tout dans l'isolate. Ne capture que ses
/// paramètres, donc peut y partir.
KindIndex Function(String) indexParser(ContentKind kind, Set<String> visible) =>
    (text) {
      final byCategory = <String, List<CatalogItem>>{};
      for (final item in parseCatalogItems(text, kind)) {
        final category = item.categoryId;
        if (category != null && visible.contains(category)) {
          byCategory.putIfAbsent(category, () => []).add(item);
        }
      }
      return KindIndex(
        entriesOf([for (final items in byCategory.values) ...items]),
        {
          for (final MapEntry(:key, :value) in byCategory.entries)
            key: entriesOf(value),
        },
        visible,
      );
    };

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

/// Index des films ou des séries du compte actif : une seule requête pour
/// tout le type, gardée 24 h. Chargé en arrière-plan dès l'accueil affiché
/// (voir `HomeShell`), puis gardé tant que l'accueil existe ; refait au
/// changement de compte, de filtre ou de catégories, en relisant le cache.
/// Les films et les séries sont indépendants : l'échec de l'un ne bloque
/// pas l'autre.
final catalogIndexProvider = AsyncNotifierProvider.autoDispose
    .family<CatalogIndexNotifier, Loaded<KindIndex>, ContentKind>(
      CatalogIndexNotifier.new,
      retry: noRetry,
    );

class CatalogIndexNotifier extends AsyncNotifier<Loaded<KindIndex>> {
  CatalogIndexNotifier(this.kind);

  final ContentKind kind;

  /// Redemander la liste au serveur au prochain calcul, même si le cache
  /// est récent ([refresh]).
  var _stale = false;

  @override
  Future<Loaded<KindIndex>> build() async {
    final repository = ref.watch(catalogRepositoryProvider);
    final filter = ref.watch(catalogFilterProvider);
    final categories = ref.watch(categoriesProvider(kind).future);
    final refresh = _stale;
    _stale = false;
    final visible = {
      for (final category in filter.apply(kind, (await categories).value))
        category.id,
    };
    return repository.all(kind, indexParser(kind, visible), refresh: refresh);
  }

  /// « Actualiser » : redemande la liste complète au serveur. Les données
  /// affichées restent en place pendant le chargement. Une erreur reste dans
  /// l'état, pour les écrans qui la montrent, sans être relancée ici.
  Future<void> refresh() async {
    _stale = true;
    ref.invalidateSelf();
    try {
      await future;
    } on Object {
      // Les grilles et la recherche affichent l'erreur et « Réessayer ».
    }
  }
}

/// Affiches d'une catégorie, prises dans l'index de son type : aucune
/// requête par catégorie. Se met à jour avec l'index (« Actualiser »,
/// filtre), en gardant l'ancienne grille pendant le calcul.
final itemsProvider = FutureProvider.autoDispose
    .family<Loaded<List<CatalogEntry>>?, (ContentKind, String)>((
      ref,
      key,
    ) async {
      final (kind, categoryId) = key;
      final index = await ref.watch(catalogIndexProvider(kind).future);
      final entries = index.value.entriesIn(categoryId);
      // Catégorie tout juste affichée (pays coché), pas encore dans l'index :
      // il se refait ; `null` d'ici là, à montrer comme un chargement.
      if (entries == null) return null;
      return Loaded(entries, offline: index.offline, savedAt: index.savedAt);
    }, retry: noRetry);
