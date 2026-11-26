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

  /// Titre des affiches : le film, ou la série et `S1E2`.
  String get shortTitle => isEpisode ? '$name · S${season}E$episode' : name;

  /// De quoi ouvrir la fiche : celle du film, ou celle de la série pour un
  /// épisode. Elle recharge le reste depuis le serveur.
  CatalogItem get catalogItem => CatalogItem(
    kind: isEpisode ? ContentKind.series : ContentKind.movies,
    id: seriesId ?? id,
    name: name,
    poster: poster,
  );

  /// Titre affiché dans le lecteur : avec celui de l'épisode, s'il en a un.
  String get title =>
      episodeTitle == null ? shortTitle : '$shortTitle · $episodeTitle';

  /// Lit les champs d'une entrée de `library.json` ou `downloads.json` de
  /// clé [key] ; `null` si l'entrée est illisible.
  static PlayItem? fromJson(String key, Map<String, Object?> map) {
    final id = key.startsWith('movie:') || key.startsWith('episode:')
        ? key.substring(key.indexOf(':') + 1)
        : null;
    final name = asString(map['name']);
    final extension = asString(map['extension']);
    if (id == null || id.isEmpty || name == null || extension == null) {
      return null;
    }
    if (!key.startsWith('episode:')) {
      return PlayItem.movie(
        id: id,
        extension: extension,
        name: name,
        poster: asString(map['poster']),
      );
    }
    final seriesId = asId(map['seriesId']);
    final season = asInt(map['season']);
    final episode = asInt(map['episode']);
    if (seriesId == null || season == null || episode == null) return null;
    return PlayItem.episode(
      id: id,
      extension: extension,
      name: name,
      seriesId: seriesId,
      season: season,
      episode: episode,
      // Enregistrés avant D-061 : avec le préfixe du fournisseur.
      episodeTitle: switch (asString(map['title'])) {
        final title? => withoutEpisodePrefix(title),
        null => null,
      },
      poster: asString(map['poster']),
    );
  }

  /// Champs de l'entrée, sans la clé ([key]).
  Map<String, Object?> toJson() => {
    if (isEpisode) ...{
      'seriesId': seriesId,
      'season': season,
      'episode': episode,
      'title': ?episodeTitle,
    },
    'name': name,
    'poster': ?poster,
    'extension': extension,
  };
}

/// Clé d'un film ou d'une série du catalogue dans `library.json` : celle de
/// son favori et, pour un film, de sa progression ([PlayItem.key]).
extension LibraryKey on CatalogItem {
  /// `movie:<id>` ou `series:<id>`.
  String get libraryKey => switch (kind) {
    ContentKind.movies => 'movie:$id',
    ContentKind.series => 'series:$id',
  };
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

  /// Vu et arrêté à la fin. Un contenu vu puis revu en partie ne l'est
  /// plus : la coche « vu » reste, mais on peut le reprendre.
  bool get finished =>
      watched && (duration <= Duration.zero || reachesEnd(position, duration));

  /// Position où proposer de reprendre, ou `null`.
  Duration? get resumeAt =>
      !finished && position >= minResume && !reachesEnd(position, duration)
      ? position
      : null;

  /// Part regardée, entre 0 et 1 ; 0 si la durée est inconnue.
  double get fraction => duration > Duration.zero
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1)
      : 0;

  Progress copyWith({bool? hidden}) => Progress(
    item: item,
    position: position,
    duration: duration,
    watched: watched,
    hidden: hidden ?? this.hidden,
    updatedAt: updatedAt,
  );

  static Progress? fromJson(String key, Object? json) {
    final map = asMap(json);
    final item = PlayItem.fromJson(key, map);
    if (item == null) return null;
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
    ...item.toJson(),
    'position': position.inSeconds,
    'duration': duration.inSeconds,
    'watched': watched,
    'hidden': hidden,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

/// Une chaîne du direct gardée dans `library.json` : favorite, ou regardée
/// depuis peu. `library` n'importe pas `live` (D-084) : de quoi l'afficher et
/// l'ouvrir par son id, sans recharger la liste des chaînes.
final class SavedChannel {
  const SavedChannel({
    required this.id,
    required this.name,
    this.number,
    this.logo,
    required this.at,
  });

  /// `stream_id` du serveur.
  final String id;
  final String name;
  final int? number;
  final String? logo;

  /// Ajoutée aux favorites, ou regardée pour la dernière fois.
  final DateTime at;

  static SavedChannel? fromJson(Object? json) {
    final map = asMap(json);
    final id = asId(map['id']);
    final name = asString(map['name']);
    if (id == null || id.isEmpty || name == null) return null;
    return SavedChannel(
      id: id,
      name: name,
      number: asInt(map['number']),
      logo: asUrl(map['logo']),
      at: _date(map['at']),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'number': ?number,
    'logo': ?logo,
    'at': at.toUtc().toIso8601String(),
  };
}

/// Favoris, progression et chaînes d'un compte : le contenu de
/// `library.json` (règle 7), valeur immuable.
///
/// Les chaînes ont leur section à part, `channels`, jamais dans `favorites` :
/// « Ma liste » et l'accueil y prendraient une chaîne pour un film. Section
/// facultative, écrite seulement si elle a quelque chose : `version` reste 1,
/// une version d'avant la lit sans erreur (D-089).
final class Library {
  const Library({
    this.favorites = const {},
    this.progress = const {},
    this.channelFavorites = const [],
    this.recentChannels = const [],
  });

  static const version = 1;

  /// Chaînes récentes gardées.
  static const maxRecentChannels = 10;

  final Map<String, Favorite> favorites;
  final Map<String, Progress> progress;

  /// Chaînes favorites, dans l'ordre d'ajout.
  final List<SavedChannel> channelFavorites;

  /// Chaînes regardées, la plus récente en premier, sans doublon.
  final List<SavedChannel> recentChannels;

  /// Lit `library.json` ; les entrées illisibles sont ignorées une à une.
  factory Library.fromJson(Object? json) {
    final map = asMap(json);
    final channels = asMap(map['channels']);
    return Library(
      favorites: {
        for (final MapEntry(:key, :value) in asMap(map['favorites']).entries)
          key: ?Favorite.fromJson(key, value),
      },
      progress: {
        for (final MapEntry(:key, :value) in asMap(map['progress']).entries)
          key: ?Progress.fromJson(key, value),
      },
      channelFavorites: _channels(channels['favorites']),
      recentChannels: _channels(channels['recent'])
          .take(maxRecentChannels)
          .toList(),
    );
  }

  /// Chaînes lisibles de [json], la première de chaque id seulement.
  static List<SavedChannel> _channels(Object? json) {
    final seen = <String>{};
    return [
      for (final entry in asList(json))
        if (SavedChannel.fromJson(entry) case final channel?
            when seen.add(channel.id))
          channel,
    ];
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
    if (channelFavorites.isNotEmpty || recentChannels.isNotEmpty)
      'channels': {
        'favorites': [for (final c in channelFavorites) c.toJson()],
        'recent': [for (final c in recentChannels) c.toJson()],
      },
  };

  Library _copy({
    Map<String, Favorite>? favorites,
    Map<String, Progress>? progress,
    List<SavedChannel>? channelFavorites,
    List<SavedChannel>? recentChannels,
  }) => Library(
    favorites: favorites ?? this.favorites,
    progress: progress ?? this.progress,
    channelFavorites: channelFavorites ?? this.channelFavorites,
    recentChannels: recentChannels ?? this.recentChannels,
  );

  /// Favoris, le plus récent en premier.
  List<Favorite> get favoritesByDate =>
      favorites.values.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  Library withFavorite(Favorite favorite) =>
      _copy(favorites: {...favorites, favorite.key: favorite});

  Library withoutFavorite(String key) =>
      _copy(favorites: {...favorites}..remove(key));

  Library withProgress(Progress entry) =>
      _copy(progress: {...progress, entry.item.key: entry});

  /// Sans la progression de [key] : plus de reprise, plus de marque « vu ».
  Library withoutProgress(String key) =>
      _copy(progress: {...progress}..remove(key));

  /// Historique vidé, chaînes récentes comprises ; favoris et chaînes
  /// favorites intacts.
  Library withoutHistory() =>
      _copy(progress: const {}, recentChannels: const []);

  bool isChannelFavorite(String id) => channelFavorites.any((c) => c.id == id);

  /// Ajoutée à la fin ; déjà favorite, elle garde sa place.
  Library withChannelFavorite(SavedChannel channel) =>
      isChannelFavorite(channel.id)
      ? this
      : _copy(channelFavorites: [...channelFavorites, channel]);

  Library withoutChannelFavorite(String id) => _copy(
    channelFavorites: [
      for (final c in channelFavorites)
        if (c.id != id) c,
    ],
  );

  /// [channel] en tête des récentes, son ancienne place retirée, la plus
  /// ancienne oubliée au-delà de [maxRecentChannels].
  Library withRecentChannel(SavedChannel channel) => _copy(
    recentChannels: [
      channel,
      ...recentChannels.where((c) => c.id != channel.id),
    ].take(maxRecentChannels).toList(),
  );

  /// Historique : tout ce qui a été lu, retirés de « Continuer à regarder »
  /// et vus compris, du plus récent au plus ancien.
  List<Progress> get history =>
      progress.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// « Vus » : ce qui porte la marque « vu » (fini, ou coché à la main), un
  /// film ou un épisode par entrée, du plus récent au plus ancien.
  List<Progress> get seen => [
    for (final entry in history)
      if (entry.watched) entry,
  ];

  /// « Continuer à regarder », du plus récent au plus ancien : les films
  /// commencés (30 s ou plus) et pas finis, et une entrée par série, son
  /// épisode regardé en dernier quel que soit son numéro, même à peine
  /// commencé. Si cet épisode est fini ([Progress.finished]), l'accueil
  /// propose l'épisode suivant. Retirée, la série n'y est plus, sans
  /// ressortir un épisode plus ancien.
  List<Progress> get continueWatching {
    final latest = <String, Progress>{};
    for (final entry in progress.values) {
      final key = entry.item.seriesId ?? entry.item.key;
      if (latest[key] case final other?
          when !entry.updatedAt.isAfter(other.updatedAt)) {
        continue;
      }
      latest[key] = entry;
    }
    return [
      for (final entry in latest.values)
        if (!entry.hidden &&
            (entry.item.isEpisode ||
                (!entry.finished && entry.position >= Progress.minResume)))
          entry,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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
