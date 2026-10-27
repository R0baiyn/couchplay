import 'dart:convert';

import 'item_name.dart';
import 'json_read.dart';

/// État de l'abonnement, tel que le serveur le décrit dans `user_info`.
final class AccountInfo {
  const AccountInfo({
    required this.status,
    this.expiresAt,
    this.maxConnections,
    this.activeConnections,
    this.isTrial = false,
  });

  /// Lit `user_info` ; les champs absents ou illisibles restent à `null`.
  factory AccountInfo.fromJson(Map<String, Object?> userInfo) => AccountInfo(
    status: asString(userInfo['status'])?.trim() ?? 'Inconnu',
    expiresAt: asDate(userInfo['exp_date']),
    maxConnections: asInt(userInfo['max_connections']),
    activeConnections: asInt(userInfo['active_cons']),
    isTrial: asBool(userInfo['is_trial']) ?? false,
  );

  /// Texte du serveur, en anglais : `Active`, `Expired`, `Banned`, `Disabled`…
  final String status;

  /// `null` quand l'abonnement n'expire pas.
  final DateTime? expiresAt;

  final int? maxConnections;
  final int? activeConnections;
  final bool isTrial;

  bool get isActive => status.toLowerCase() == 'active';
}

/// Films ou séries : les deux moitiés du catalogue, mêmes écrans.
enum ContentKind {
  movies('get_vod_categories', 'get_vod_streams'),
  series('get_series_categories', 'get_series');

  const ContentKind(this.categoriesAction, this.listAction);

  final String categoriesAction;
  final String listAction;
}

final class Category {
  const Category({required this.id, required this.name});

  final String id;
  final String name;
}

/// Un film ou une série dans une liste : de quoi afficher une affiche.
final class CatalogItem {
  const CatalogItem({
    required this.kind,
    required this.id,
    required this.name,
    this.poster,
    this.categoryId,
    this.tmdbId,
    this.extension,
    ItemName? parsedName,
  }) : _parsedName = parsedName;

  final ContentKind kind;
  final String id;
  final String name;
  final String? poster;
  final String? categoryId;
  final String? tmdbId;

  /// Extension du fichier d'un film (`mkv`, `mp4`…) ; `null` pour une série.
  final String? extension;

  final ItemName? _parsedName;

  /// [name] décomposé. Les listes du serveur le calculent au décodage ; une
  /// entrée faite à la main (favori) le calcule à la demande.
  ItemName get parsedName => _parsedName ?? ItemName.parse(name);
}

/// En-tête commun des fiches film et série.
final class Details {
  const Details({
    required this.name,
    this.poster,
    this.backdrop,
    this.year,
    this.duration,
    this.genre,
    this.rating,
    this.plot,
    this.director,
    this.cast,
  });

  final String name;
  final String? poster;
  final String? backdrop;
  final int? year;
  final Duration? duration;
  final String? genre;

  /// Note sur 10.
  final double? rating;
  final String? plot;
  final String? director;
  final String? cast;
}

final class MovieDetails {
  const MovieDetails({required this.details, this.extension});

  final Details details;
  final String? extension;
}

final class Episode {
  const Episode({
    required this.id,
    required this.number,
    required this.title,
    this.extension,
    this.plot,
    this.duration,
    this.image,
  });

  final String id;
  final int number;
  final String title;
  final String? extension;
  final String? plot;
  final Duration? duration;
  final String? image;
}

final class Season {
  const Season({
    required this.number,
    required this.name,
    required this.episodes,
  });

  final int number;
  final String name;

  /// Triés par numéro, jamais vide.
  final List<Episode> episodes;
}

final class SeriesDetails {
  const SeriesDetails({required this.details, required this.seasons});

  final Details details;

  /// Triées par numéro ; seules les saisons qui ont des épisodes.
  final List<Season> seasons;
}

// Lecture des réponses du serveur. Fonctions de premier niveau : elles
// tournent dans un isolate (règle 5). Une entrée invalide est ignorée.

List<Category> parseCategories(String text) => [
  for (final entry in asList(jsonDecode(text))) ?_category(asMap(entry)),
];

Category? _category(Map<String, Object?> map) {
  final id = asId(map['category_id']);
  final name = asString(map['category_name'])?.trim();
  return id == null || name == null ? null : Category(id: id, name: name);
}

List<CatalogItem> parseCatalogItems(String text, ContentKind kind) => [
  for (final entry in asList(jsonDecode(text))) ?_item(asMap(entry), kind),
];

CatalogItem? _item(Map<String, Object?> map, ContentKind kind) {
  final movie = kind == ContentKind.movies;
  final id = asId(map[movie ? 'stream_id' : 'series_id']);
  final name = asString(map['name'])?.trim();
  if (id == null || name == null) return null;
  return CatalogItem(
    kind: kind,
    id: id,
    name: name,
    poster: _url(map[movie ? 'stream_icon' : 'cover']),
    categoryId: asId(map['category_id']),
    tmdbId: _tmdb(map['tmdb_id'] ?? map['tmdb']),
    extension: movie ? asString(map['container_extension'])?.trim() : null,
    parsedName: ItemName.parse(name),
  );
}

MovieDetails parseMovieDetails(String text) {
  final body = asMap(jsonDecode(text));
  final data = asMap(body['movie_data']);
  return MovieDetails(
    details: _details(
      asMap(body['info']),
      fallbackName: asString(data['name']),
    ),
    extension: asString(data['container_extension'])?.trim(),
  );
}

SeriesDetails parseSeriesDetails(String text) {
  final body = asMap(jsonDecode(text));
  // Les noms viennent de `seasons`, qui peut lister des saisons absentes :
  // seules les clés de `episodes` décident des saisons affichées.
  final names = <int, String>{};
  for (final entry in asList(body['seasons'])) {
    final season = asMap(entry);
    final number = asInt(season['season_number']);
    final name = asString(season['name'])?.trim();
    if (number != null && name != null) names[number] = name;
  }
  final seasons = <Season>[];
  for (final MapEntry(:key, :value) in asMap(body['episodes']).entries) {
    final number = asInt(key);
    final episodes = [
      for (final entry in asList(value)) ?_episode(asMap(entry)),
    ]..sort((a, b) => a.number.compareTo(b.number));
    if (number == null || episodes.isEmpty) continue;
    seasons.add(
      Season(
        number: number,
        name:
            names[number] ??
            (number == 0 ? 'Épisodes spéciaux' : 'Saison $number'),
        episodes: episodes,
      ),
    );
  }
  seasons.sort((a, b) => a.number.compareTo(b.number));
  return SeriesDetails(
    details: _details(asMap(body['info'])),
    seasons: seasons,
  );
}

Episode? _episode(Map<String, Object?> map) {
  final id = asId(map['id']);
  final number = asInt(map['episode_num']);
  if (id == null || number == null) return null;
  final info = asMap(map['info']);
  return Episode(
    id: id,
    number: number,
    title: asString(map['title'])?.trim() ?? 'Épisode $number',
    extension: asString(map['container_extension'])?.trim(),
    plot: asString(info['plot'])?.trim(),
    duration: _duration(info),
    image: _url(info['movie_image']),
  );
}

Details _details(Map<String, Object?> info, {String? fallbackName}) {
  final name =
      asString(info['name'])?.trim() ?? fallbackName?.trim() ?? 'Sans titre';
  final release = asString(info['releasedate'] ?? info['releaseDate']);
  final rating = asDouble(info['rating']);
  return Details(
    name: name,
    poster:
        _url(info['movie_image']) ??
        _url(info['cover_big']) ??
        _url(info['cover']),
    // Liste d'URL en général, parfois une seule chaîne.
    backdrop:
        _url(asList(info['backdrop_path']).firstOrNull) ??
        _url(info['backdrop_path']),
    year: _year(release) ?? _year(_yearInName.firstMatch(name)?[1]),
    duration: _duration(info),
    genre: asString(info['genre'])?.trim(),
    rating: rating != null && rating > 0 ? rating : null,
    plot: (asString(info['plot']) ?? asString(info['description']))?.trim(),
    director: asString(info['director'])?.trim(),
    cast: (asString(info['cast']) ?? asString(info['actors']))?.trim(),
  );
}

final _yearInName = RegExp(r'\((\d{4})\)');

/// URL http(s) seulement : les serveurs renvoient parfois un texte vide ou un
/// chemin relatif inutilisable.
String? _url(Object? value) {
  final text = asString(value)?.trim();
  if (text == null) return null;
  return text.startsWith('http://') || text.startsWith('https://')
      ? text
      : null;
}

String? _tmdb(Object? value) {
  final id = asId(value);
  return id == null || id == '0' ? null : id;
}

/// Année d'une date `AAAA-MM-JJ`, ou d'un texte `AAAA`.
int? _year(String? text) {
  final year = int.tryParse(text?.trim().split('-').first ?? '');
  return year != null && year > 1800 ? year : null;
}

/// `duration_secs`, sinon `duration` au format `hh:mm:ss` ; `null` si nulle.
Duration? _duration(Map<String, Object?> info) {
  var seconds = asInt(info['duration_secs']) ?? 0;
  if (seconds <= 0) {
    final parts = (asString(info['duration']) ?? '')
        .split(':')
        .map(int.tryParse)
        .toList();
    if (parts.length == 3 && !parts.contains(null)) {
      seconds = parts[0]! * 3600 + parts[1]! * 60 + parts[2]!;
    }
  }
  return seconds > 0 ? Duration(seconds: seconds) : null;
}
