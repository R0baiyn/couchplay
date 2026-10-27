/// Nom d'un film ou d'une série tel que le serveur l'écrit, décomposé :
/// « FR · Libre (2024) HD VF » donne le titre « Libre (2024) », l'année 2024,
/// la qualité « HD » et la langue « VF ».
///
/// Calculé une fois, au décodage des listes (dans l'isolate) : la recherche
/// et le regroupement des versions ne font ensuite que comparer des textes.
final class ItemName {
  const ItemName({
    required this.display,
    required this.text,
    this.year,
    this.quality,
    this.language,
  });

  factory ItemName.parse(String name) {
    final match = _country.firstMatch(name);
    var title = match == null ? name : name.substring(match.end);
    String? quality;
    String? language;
    title = title.replaceAllMapped(_label, (m) {
      final token = m[0]!;
      if (_qualityRanks.containsKey(token)) {
        quality ??= token;
      } else {
        language ??= token;
      }
      return ' ';
    });
    title = title
        .replaceAll(_emptyBrackets, ' ')
        .replaceAll(_spaces, ' ')
        .trim()
        .replaceAll(_trailingSeparator, '');
    final year = int.tryParse(_year.firstMatch(title)?[1] ?? '');
    return ItemName(
      display: title.isEmpty ? name.trim() : title,
      text: normalize(title.replaceAll(_year, ' ')),
      year: year != null && year >= 1900 && year <= 2100 ? year : null,
      quality: quality,
      language: language,
    );
  }

  /// Titre à afficher : sans préfixe pays ni étiquettes, année gardée.
  final String display;

  /// Titre pour la recherche ([normalize]), sans l'année.
  final String text;

  /// Année entre parenthèses dans le nom, seulement : « Blade Runner 2049 »
  /// n'a pas d'année.
  final int? year;

  /// Étiquette de qualité telle qu'écrite : `4K`, `FHD`, `HD`, `SD`…
  final String? quality;

  /// Étiquette de langue telle qu'écrite : `VF`, `MULTI`, `VOSTFR`…
  final String? language;

  /// « HD VF », « 4K », « MULTI » ; `null` si le nom ne dit rien.
  String? get label => switch ((quality, language)) {
    (null, null) => null,
    (final q?, null) => q,
    (null, final l?) => l,
    (final q?, final l?) => '$q $l',
  };

  /// Rang de la qualité : 4K avant FHD, avant HD, avant SD. Sans étiquette,
  /// entre HD et SD : ces entrées sont souvent l'original, rarement du SD.
  int get qualityRank => _qualityRanks[quality] ?? 15;

  /// Audio sans doute en français : faux pour une version originale.
  bool get frenchAudio => !_originalLanguages.contains(language);
}

/// Texte ramené à l'essentiel pour comparer : minuscules, sans accents,
/// ponctuation remplacée par des espaces, espaces simples.
/// « L'Été  d'Amélie ! » donne « l ete d amelie ».
String normalize(String text) {
  final out = StringBuffer();
  var space = true;
  for (final rune in text.toLowerCase().runes) {
    final String? piece;
    if ((rune >= 0x61 && rune <= 0x7a) || (rune >= 0x30 && rune <= 0x39)) {
      piece = String.fromCharCode(rune);
    } else if (rune < 0x80 || _separators.contains(rune)) {
      piece = null;
    } else {
      // Lettres d'autres alphabets gardées telles quelles : un titre arabe
      // reste trouvable par ses propres lettres.
      piece = _folded[rune] ?? String.fromCharCode(rune);
    }
    if (piece == null) {
      if (!space) out.write(' ');
      space = true;
    } else {
      out.write(piece);
      space = false;
    }
  }
  final result = out.toString();
  return result.endsWith(' ') ? result.substring(0, result.length - 1) : result;
}

// Préfixe pays, seulement parmi des codes connus, et suivi d'un séparateur :
// « FR · Drame », « FR - Inception », « |FR| Titre ». « ABBA - Gold »,
// « DBZ : … » ou « IT (2017) » gardent leur nom.
final _country = RegExp(
  r'^\s*(?:\|\s*(?:' +
      _countries +
      r')\s*\||(?:' +
      _countries +
      r')\s*[·|:\-])\s*',
);
const _countries = 'FR|EN|UK|US|ES|IT|DE|PT|NL|AR|TR|DZ|MA|TN|BE|CA|CH|VOST';

// Étiquettes, en majuscules et en mots entiers : `HD` ne se trouve pas dans
// `FHD`, ni « vo » dans un titre en minuscules.
final _label = RegExp(
  r'(?<![A-Za-z0-9])(?:4K|UHD|2160[pP]|HDR|FHD|1080[pP]|HD|720[pP]|SD|'
  r'MULTI|TRUEFRENCH|FRENCH|VFF|VFQ|VFI|VOF|VF|VOSTFR|VOST|VO)'
  r'(?![A-Za-z0-9])',
);

const _qualityRanks = {
  '4K': 40,
  'UHD': 40,
  '2160p': 40,
  '2160P': 40,
  'HDR': 40,
  'FHD': 30,
  '1080p': 30,
  '1080P': 30,
  'HD': 20,
  '720p': 20,
  '720P': 20,
  'SD': 10,
};

const _originalLanguages = {'VO', 'VOST', 'VOSTFR'};

final _year = RegExp(r'\((\d{4})\)');
final _emptyBrackets = RegExp(r'\(\s*\)|\[\s*\]');
final _spaces = RegExp(r'\s+');
final _trailingSeparator = RegExp(r'\s*[-·|:]+$');

// Ponctuation hors ASCII, vue dans les noms réels : espace insécable,
// apostrophes et guillemets typographiques, tirets, point médian, points
// de suspension.
const _separators = {
  0x00a0, 0x00ab, 0x00b7, 0x00bb, 0x2013, 0x2014, 0x2018, 0x2019, //
  0x201c, 0x201d, 0x2026, 0x202f,
};

// Accents du français (et des voisins les plus courants), en minuscules :
// [normalize] passe le texte en minuscules avant.
const _folded = {
  0xe0: 'a', 0xe1: 'a', 0xe2: 'a', 0xe3: 'a', 0xe4: 'a', 0xe5: 'a', //
  0xe6: 'ae', 0xe7: 'c', 0xe8: 'e', 0xe9: 'e', 0xea: 'e', 0xeb: 'e',
  0xec: 'i', 0xed: 'i', 0xee: 'i', 0xef: 'i', 0xf1: 'n', 0xf2: 'o',
  0xf3: 'o', 0xf4: 'o', 0xf5: 'o', 0xf6: 'o', 0xf8: 'o', 0xf9: 'u',
  0xfa: 'u', 0xfb: 'u', 0xfc: 'u', 0xfd: 'y', 0xff: 'y', 0x0153: 'oe',
};
