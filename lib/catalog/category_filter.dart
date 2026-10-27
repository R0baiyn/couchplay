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

  bool isVisible(ContentKind kind, Category category) {
    final forced = overrides[overrideKey(kind, category.id)];
    if (forced != null) return forced;
    if (!showAdult && isAdultCategory(category.name)) return false;
    final tag = categoryTag(category.name);
    return tag == null || tags.isEmpty || tags.contains(tag);
  }

  List<Category> apply(ContentKind kind, Iterable<Category> categories) => [
    for (final category in categories)
      if (isVisible(kind, category)) category,
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
  return null;
}

// Mots-clés adultes, sur le nom en majuscules. Volontairement sans repli des
// caractères sosies : la catégorie « ANIMÉES POUR ADUƖTES » (Ɩ au lieu de L)
// contient des animés grand public et doit rester visible.
final _adult = RegExp(r'XXX|PORN|ADULT|\+ ?18|18 ?\+|-18\b');

bool isAdultCategory(String name) => _adult.hasMatch(name.toUpperCase());

/// Pays détectés dans [categories], triés, pour les réglages.
List<String> detectTags(Iterable<Category> categories) =>
    {for (final c in categories) ?categoryTag(c.name)}.toList()..sort();
