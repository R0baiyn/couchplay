import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/versions.dart';
import '../live/channel.dart';
import '../live/live_providers.dart';
import '../server/item_name.dart';

/// Mots d'une recherche, normalisés comme les titres ([normalize]).
List<String> queryWords(String query) => [
  for (final word in normalize(query).split(' '))
    if (word.isNotEmpty) word,
];

/// Éléments de [items] dont un des textes normalisés ([texts]) contient
/// chaque mot de [query], dans l'ordre de [items] ; ceux dont un texte
/// commence par la recherche passent devant. Une recherche vide garde tout.
List<T> _rank<T>(
  List<T> items,
  Iterable<String> Function(T) texts,
  String query,
) {
  final words = queryWords(query);
  if (words.isEmpty) return items;
  final start = words.join(' ');
  final first = <T>[];
  final rest = <T>[];
  for (final item in items) {
    var matches = false;
    var starts = false;
    for (final text in texts(item)) {
      if (words.every(text.contains)) {
        matches = true;
        if (text.startsWith(start)) {
          starts = true;
          break;
        }
      }
    }
    if (matches) (starts ? first : rest).add(item);
  }
  return [...first, ...rest];
}

/// Affiches dont un titre (de n'importe quelle version) contient chaque mot
/// de [query], dans l'ordre de [entries] ; celles dont le titre commence par
/// la recherche passent devant. Une recherche vide garde tout.
List<CatalogEntry> search(List<CatalogEntry> entries, String query) => _rank(
  entries,
  (entry) => entry.versions.map((version) => version.parsedName.text),
  query,
);

/// Une chaîne et son nom normalisé, calculé une fois par liste de chaînes.
typedef SearchableChannel = ({Channel channel, String text});

/// Chaînes visibles prêtes à chercher : refaites seulement quand la liste
/// ou le filtre changent, pas à chaque frappe. Sans valeur pendant un
/// rechargement ou après un échec (`whenData`) : jamais la liste de l'ancien
/// compte après un changement de compte.
final channelSearchIndexProvider =
    Provider.autoDispose<AsyncValue<List<SearchableChannel>>>(
      (ref) => ref
          .watch(visibleChannelsProvider)
          .whenData(
            (channels) => [
              for (final channel in channels)
                (channel: channel, text: normalize(channel.name)),
            ],
          ),
    );

/// Chaînes dont le nom contient chaque mot de [query], même règle que
/// [search]. Les variantes d'une chaîne (`FHD`, `SD`) restent séparées.
List<Channel> searchChannels(List<SearchableChannel> index, String query) => [
  for (final (:channel, text: _) in _rank(index, (c) => [c.text], query))
    channel,
];

/// Puces des résultats ; leurs noms sont ceux des Keys `search.filter.*`.
enum SearchFilter { all, movies, series, live }

/// Sections à afficher sous les puces, dans l'ordre : Films, Séries, puis TV.
/// Une puce choisie ne garde que la sienne ; liste vide si elle n'a rien.
/// `null` : rien à montrer encore, les chaînes chargent toujours
/// ([channelsPending]).
List<SearchFilter>? searchSections(
  SearchFilter filter, {
  required bool movies,
  required bool series,
  required bool channels,
  required bool channelsPending,
}) {
  final shown = [
    for (final (section, found) in [
      (SearchFilter.movies, movies),
      (SearchFilter.series, series),
      (SearchFilter.live, channels),
    ])
      if (found && (filter == SearchFilter.all || filter == section)) section,
  ];
  final waiting =
      channelsPending &&
      (filter == SearchFilter.all || filter == SearchFilter.live);
  return shown.isEmpty && waiting ? null : shown;
}
