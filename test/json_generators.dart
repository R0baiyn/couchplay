import 'dart:math';

import 'package:couchplay/library/library.dart';

/// Générateur maison pour les tests d'aller-retour des fichiers locaux : une
/// graine fixe, donc la même suite à chaque lancement. Aucun identifiant ni
/// URL réels : que des valeurs fictives et des valeurs limites.
final class Gen {
  Gen(int seed) : random = Random(seed);

  final Random random;

  bool chance([double p = 0.5]) => random.nextDouble() < p;

  T pick<T>(List<T> values) => values[random.nextInt(values.length)];

  int between(int min, int max) => min + random.nextInt(max - min + 1);

  static const _edgeTexts = [
    'a',
    'Mirage',
    'é',
    '日本語の題名',
    'عنوان',
    '😀🎬 emoji',
    '👨‍👩‍👧 famille',
    ' espace devant',
    'espace derrière ',
    'guillemets " et \\ et \n et \t',
    '{"json": [1, 2]}',
    '0',
    '12',
    'null',
    'true',
    'affiche/12.jpg',
  ];

  /// Texte non vide et non blanc : `asString` ignore les textes blancs, une
  /// entrée à nom blanc n'est donc pas relue (voir les tests « abîmé »).
  String text() {
    if (chance(0.3)) return pick(_edgeTexts);
    if (chance(0.03)) return 'x' * between(2000, 6000);
    const alphabet = 'abcXYZ019 é日😀-_:.';
    final runes = alphabet.runes.toList();
    final length = between(1, 24);
    final buffer = StringBuffer('a');
    for (var i = 0; i < length; i++) {
      buffer.writeCharCode(pick(runes));
    }
    return buffer.toString();
  }

  /// Identifiant sûr pour un nom de fichier : `[A-Za-z0-9_-]{1,64}`.
  String safeId() {
    if (chance(0.15)) return pick(['0', '1', '9', '0' * 64, 'a-b_c', 'Z']);
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-';
    return [
      for (var i = 0; i < between(1, 64); i++)
        alphabet[random.nextInt(alphabet.length)],
    ].join();
  }

  /// Entier de durée ou de numéro : 0, petits, grands.
  int count() => pick([
    0,
    1,
    29,
    30,
    90,
    between(0, 100000),
    between(0, 100000),
    1000000000,
    4000000000000,
  ]);

  DateTime date() => DateTime.utc(
    between(1971, 2060),
    between(1, 12),
    between(1, 28),
    between(0, 23),
    between(0, 59),
    between(0, 59),
    between(0, 999),
    chance() ? between(0, 999) : 0,
  );

  String? poster() => chance() ? text() : null;

  PlayItem item({bool safe = true, bool? episode}) {
    final isEpisode = episode ?? chance();
    final id = safeId();
    final extension = pick([
      'mkv',
      'mp4',
      'avi',
      'M4V',
      'ts',
      'a',
      '0123456789',
    ]);
    final name = text();
    if (!isEpisode) {
      return PlayItem.movie(
        id: id,
        extension: extension,
        name: name,
        poster: poster(),
      );
    }
    return PlayItem.episode(
      id: id,
      extension: extension,
      name: name,
      seriesId: safeId(),
      season: count(),
      episode: count(),
      episodeTitle: chance() ? text() : null,
      poster: poster(),
    );
  }

  Favorite favorite() {
    final key = '${pick(['movie', 'series'])}:${safeId()}';
    return Favorite(key: key, name: text(), poster: poster(), addedAt: date());
  }

  Progress progress() => Progress(
    item: item(),
    position: Duration(seconds: count()),
    duration: Duration(seconds: count()),
    watched: chance(),
    hidden: chance(),
    updatedAt: date(),
  );

  Library library() {
    var library = const Library();
    for (var i = 0; i < between(0, 6); i++) {
      library = library.withFavorite(favorite());
    }
    for (var i = 0; i < between(0, 6); i++) {
      library = library.withProgress(progress());
    }
    return library;
  }

  static const _junk = <Object?>[
    null,
    true,
    false,
    0,
    -1,
    1,
    9223372036854775807,
    -9223372036854775808,
    1e300,
    -0.5,
    double.nan,
    double.infinity,
    '',
    '   ',
    'texte',
    '12',
    '1e3',
    '0',
    [],
    {},
    [1, 'a', null],
    {'x': 1},
    1700000000000,
    9999999999999,
    99999999999999999,
  ];

  /// Copie de [json] dont des valeurs sont remplacées par n'importe quoi
  /// (mauvais type, extrême), avec des champs inconnus en plus : ce qu'un
  /// fichier édité à la main ou écrit par une autre version peut contenir.
  Object? mutate(Object? json, {double rate = 0.08}) {
    if (chance(rate)) return pick(_junk);
    return switch (json) {
      Map() => {
        for (final MapEntry(:key, :value) in json.entries)
          if (!chance(rate / 2)) key: mutate(value, rate: rate),
        if (chance(rate)) 'inconnu${between(0, 9)}': pick(_junk),
      },
      List() => [for (final value in json) mutate(value, rate: rate)],
      _ => json,
    };
  }
}
