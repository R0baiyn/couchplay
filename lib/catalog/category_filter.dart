import '../server/models.dart';

/// Choix d'affichage des catégories d'un compte.
final class CatalogFilter {
  const CatalogFilter({
    this.tags = const {'FR'},
    this.showAdult = false,
    this.overrides = const {},
  });

  /// Pays (ou langues) affichés. Vide : tous.
  final Set<String> tags;
  final bool showAdult;

  /// Choix forcés catégorie par catégorie, clé [overrideKey] : `true` affiche,
  /// `false` masque, quel que soit le reste.
  final Map<String, bool> overrides;

  static String overrideKey(ContentKind kind, String categoryId) =>
      '${kind.name}:$categoryId';

  CatalogFilter copyWith({
    Set<String>? tags,
    bool? showAdult,
    Map<String, bool>? overrides,
  }) => CatalogFilter(
    tags: tags ?? this.tags,
    showAdult: showAdult ?? this.showAdult,
    overrides: overrides ?? this.overrides,
  );

  /// Clé des exceptions du direct, à part des films et des séries (le direct
  /// n'est pas un [ContentKind], D-084).
  static String liveKey(String categoryId) => 'live:$categoryId';

  bool isVisible(ContentKind kind, Category category) =>
      _isVisible(overrideKey(kind, category.id), category, untagged: true);

  /// Même règle que [isVisible], sauf qu'une catégorie sans pays est masquée :
  /// les catégories du direct sont surtout rangées par pays (`BELGIUM`, `UK`…)
  /// sans balise lisible (D-087).
  bool isLiveVisible(Category category) =>
      _isVisible(liveKey(category.id), category, untagged: false);

  bool _isVisible(String key, Category category, {required bool untagged}) {
    final forced = overrides[key];
    if (forced != null) return forced;
    if (!showAdult && isAdultCategory(category.name)) return false;
    if (tags.isEmpty) return true;
    final tag = categoryTag(category.name);
    return tag == null ? untagged : tags.contains(tag);
  }

  List<Category> apply(ContentKind kind, Iterable<Category> categories) => [
    for (final category in categories)
      if (isVisible(kind, category)) category,
  ];

  List<Category> applyLive(Iterable<Category> categories) => [
    for (final category in categories)
      if (isLiveVisible(category)) category,
  ];
}

// Préfixe en tête du nom : « FR · Drame », « FR | Drame », « |FR| Drame »,
// « EN - Films ». De 2 à 4 lettres : « VOST » compte, « UNKNOW » non.
final _prefix = RegExp(r'^\s*\|?\s*([A-Z]{2,4})\s*[·|:\-]');

// Sans préfixe, des mots du nom trahissent la langue (séries rangées par
// plateforme). Liste tirée des catalogues réels, à compléter au besoin.
const _markers = <String, String>{
  'SUB-AR': 'AR',
  'DUB-AR': 'AR',
  'ARABE': 'AR',
  'ARABY': 'AR',
  'ALGERIEN': 'AR',
  'TUNISIEN': 'AR',
  'MAROC': 'AR',
  'TURQUE': 'TR',
};

/// Pays ou langue d'une catégorie (`FR`, `AR`, `VOST`…), `null` si inconnu.
String? categoryTag(String name) {
  if (_prefix.firstMatch(name) case final match?) return match[1];
  final upper = name.toUpperCase();
  for (final MapEntry(:key, :value) in _markers.entries) {
    if (upper.contains(key)) return value;
  }
  // Après les autres règles : ne peut que donner une balise à une catégorie
  // qui n'en avait pas (catégories du direct : `FRANCE HD`, `SPORT FR`).
  if (_frenchWord.hasMatch(upper)) return 'FR';
  return null;
}

// `FRANCE` ou `FR` en mot entier : ni `VOSTFR`, ni `FRÉQUENCES`.
final _frenchWord = RegExp(
  r'(?<![\p{L}\p{N}])FR(?:ANCE)?(?![\p{L}\p{N}])',
  unicode: true,
);

// Mots-clés adultes, sur le nom en majuscules. Volontairement sans repli des
// caractères sosies : la catégorie « ANIMÉES POUR ADUƖTES » (Ɩ au lieu de L)
// contient des animés grand public et doit rester visible.
final _adult = RegExp(r'XXX|PORN|ADULT|\+ ?18|18 ?\+|-18\b');

bool isAdultCategory(String name) => _adult.hasMatch(name.toUpperCase());

/// Pays détectés dans [categories], triés, pour les réglages.
List<String> detectTags(Iterable<Category> categories) =>
    {for (final c in categories) ?categoryTag(c.name)}.toList()..sort();
