import '../catalog/versions.dart';
import '../server/item_name.dart';

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
