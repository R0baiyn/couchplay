import '../server/json_read.dart';
import '../server/models.dart';

/// Ce qu'on regarde : un film ou un épisode, avec de quoi l'afficher et le
/// relancer sans recharger le catalogue.
final class PlayItem {
  const PlayItem.movie({
    required this.id,
    required this.extension,
    required this.name,
    this.poster,
  }) : seriesId = null,
       season = null,
       episode = null,
       episodeTitle = null;

  const PlayItem.episode({
    required this.id,
    required this.extension,
    required this.name,
    required String this.seriesId,
    required int this.season,
    required int this.episode,
    this.episodeTitle,
    this.poster,
  });

  /// Id du film ou de l'épisode sur le serveur.
  final String id;
  final String extension;

  /// Nom du film, ou de la série pour un épisode.
  final String name;
  final String? poster;

  final String? seriesId;
  final int? season;
  final int? episode;
  final String? episodeTitle;

  bool get isEpisode => seriesId != null;

  /// Clé dans `library.json` : `movie:<id>` ou `episode:<id>`.
  String get key => isEpisode ? 'episode:$id' : 'movie:$id';

  /// Titre affiché dans le lecteur.
  String get title => isEpisode
      ? '$name · S${season}E$episode${episodeTitle == null ? '' : ' · $episodeTitle'}'
      : name;
}

/// Un favori : de quoi l'afficher sur l'accueil sans recharger le catalogue.
final class Favorite {
  const Favorite({
    required this.key,
    required this.name,
    this.poster,
    required this.addedAt,
  });

  /// `movie:<id>` ou `series:<id>`.
  final String key;
  final String name;
  final String? poster;
  final DateTime addedAt;

  bool get isSeries => key.startsWith('series:');
  String get id => key.substring(key.indexOf(':') + 1);

  /// De quoi ouvrir sa fiche ; elle recharge le reste depuis le serveur.
  CatalogItem get item => CatalogItem(
    kind: isSeries ? ContentKind.series : ContentKind.movies,
    id: id,
    name: name,
    poster: poster,
  );

  static Favorite? fromJson(String key, Object? json) {
    final map = asMap(json);
    final name = asString(map['name']);
    if (name == null || !_favoriteKey.hasMatch(key)) return null;
    return Favorite(
      key: key,
      name: name,
      poster: asString(map['poster']),
      addedAt: _date(map['addedAt']),
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'poster': ?poster,
    'addedAt': addedAt.toUtc().toIso8601String(),
  };
}

/// Où on en est d'un film ou d'un épisode.
final class Progress {
  const Progress({
    required this.item,
    required this.position,
    required this.duration,
    this.watched = false,
    this.hidden = false,
    required this.updatedAt,
  });

  final PlayItem item;
  final Duration position;

  /// `Duration.zero` si inconnue.
  final Duration duration;
  final bool watched;

  /// Retiré de « Continuer à regarder », progression gardée.
  final bool hidden;
  final DateTime updatedAt;

  /// Reprendre seulement après 30 s, et pas sur un contenu vu.
  static const minResume = Duration(seconds: 30);

  /// Vu à 90 % de la durée.
  static const watchedRatio = 0.9;

  static bool reachesEnd(Duration position, Duration duration) =>
      duration > Duration.zero &&
      position.inMilliseconds >= duration.inMilliseconds * watchedRatio;

  /// Position où proposer de reprendre, ou `null`.
  Duration? get resumeAt =>
      !watched && position >= minResume && !reachesEnd(position, duration)
      ? position
      : null;

  /// Part regardée, entre 0 et 1 ; 0 si la durée est inconnue.
  double get fraction => duration > Duration.zero
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1)
      : 0;

  Progress copyWith({bool? watched, bool? hidden}) => Progress(
    item: item,
    position: position,
    duration: duration,
    watched: watched ?? this.watched,
    hidden: hidden ?? this.hidden,
    updatedAt: updatedAt,
  );

  static Progress? fromJson(String key, Object? json) {
    final map = asMap(json);
    final id = key.startsWith('movie:') || key.startsWith('episode:')
        ? key.substring(key.indexOf(':') + 1)
        : null;
    final name = asString(map['name']);
    final extension = asString(map['extension']);
    if (id == null || id.isEmpty || name == null || extension == null) {
      return null;
    }
    final PlayItem item;
    if (key.startsWith('episode:')) {
      final seriesId = asId(map['seriesId']);
      final season = asInt(map['season']);
      final episode = asInt(map['episode']);
      if (seriesId == null || season == null || episode == null) return null;
      item = PlayItem.episode(
        id: id,
        extension: extension,
        name: name,
        seriesId: seriesId,
        season: season,
        episode: episode,
        episodeTitle: asString(map['title']),
        poster: asString(map['poster']),
      );
    } else {
      item = PlayItem.movie(
        id: id,
        extension: extension,
        name: name,
        poster: asString(map['poster']),
      );
    }
    return Progress(
      item: item,
      position: Duration(seconds: asInt(map['position']) ?? 0),
      duration: Duration(seconds: asInt(map['duration']) ?? 0),
      watched: asBool(map['watched']) ?? false,
      hidden: asBool(map['hidden']) ?? false,
      updatedAt: _date(map['updatedAt']),
    );
  }

  Map<String, Object?> toJson() => {
    if (item.isEpisode) ...{
      'seriesId': item.seriesId,
      'season': item.season,
      'episode': item.episode,
      'title': ?item.episodeTitle,
    },
    'name': item.name,
    'poster': ?item.poster,
    'extension': item.extension,
    'position': position.inSeconds,
    'duration': duration.inSeconds,
    'watched': watched,
    'hidden': hidden,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

/// Favoris et progression d'un compte : le contenu de `library.json`
/// (règle 7), valeur immuable.
final class Library {
  const Library({this.favorites = const {}, this.progress = const {}});

  static const version = 1;

  final Map<String, Favorite> favorites;
  final Map<String, Progress> progress;

  /// Lit `library.json` ; les entrées illisibles sont ignorées une à une.
  factory Library.fromJson(Object? json) {
    final map = asMap(json);
    return Library(
      favorites: {
        for (final MapEntry(:key, :value) in asMap(map['favorites']).entries)
          key: ?Favorite.fromJson(key, value),
      },
      progress: {
        for (final MapEntry(:key, :value) in asMap(map['progress']).entries)
          key: ?Progress.fromJson(key, value),
      },
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'favorites': {
      for (final MapEntry(:key, :value) in favorites.entries)
        key: value.toJson(),
    },
    'progress': {
      for (final MapEntry(:key, :value) in progress.entries)
        key: value.toJson(),
    },
  };

  /// Favoris, le plus récent en premier.
  List<Favorite> get favoritesByDate =>
      favorites.values.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  Library withFavorite(Favorite favorite) => Library(
    favorites: {...favorites, favorite.key: favorite},
    progress: progress,
  );

  Library withoutFavorite(String key) =>
      Library(favorites: {...favorites}..remove(key), progress: progress);

  Library withProgress(Progress entry) => Library(
    favorites: favorites,
    progress: {...progress, entry.item.key: entry},
  );

  /// « Continuer à regarder » : commencés (30 s ou plus), ni vus ni retirés,
  /// une seule entrée par série (son épisode le plus récent), du plus récent
  /// au plus ancien.
  List<Progress> get continueWatching {
    final bySeries = <String, Progress>{};
    final movies = <Progress>[];
    for (final entry in progress.values) {
      if (entry.watched ||
          entry.hidden ||
          entry.position < Progress.minResume) {
        continue;
      }
      final seriesId = entry.item.seriesId;
      if (seriesId == null) {
        movies.add(entry);
      } else if (bySeries[seriesId] case final other?
          when !entry.updatedAt.isAfter(other.updatedAt)) {
        continue;
      } else {
        bySeries[seriesId] = entry;
      }
    }
    return [...movies, ...bySeries.values]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
}

final _favoriteKey = RegExp(r'^(movie|series):.+$');

DateTime _date(Object? value) =>
    asDate(value) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// Épisode qui suit [current] dans [series] : le suivant de la saison, sinon
/// le premier de la saison suivante. Les épisodes sans fichier connu sont
/// sautés, et avec eux une saison qui n'a que ceux-là. `null` en fin de
/// série, ou si [current] n'y figure plus.
({PlayItem item, String? image})? nextEpisode(
  SeriesDetails series,
  PlayItem current,
) {
  var found = false;
  for (final season in series.seasons) {
    for (final episode in season.episodes) {
      final extension = episode.extension;
      if (!found) {
        found = episode.id == current.id;
      } else if (extension != null) {
        return (
          item: PlayItem.episode(
            id: episode.id,
            extension: extension,
            name: current.name,
            seriesId: current.seriesId!,
            season: season.number,
            episode: episode.number,
            episodeTitle: episode.title,
            poster: current.poster,
          ),
          image: episode.image,
        );
      }
    }
  }
  return null;
}
