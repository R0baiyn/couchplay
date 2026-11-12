import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:couchplay/library/library.dart';
import 'package:couchplay/library/library_store.dart';
import 'package:couchplay/server/models.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 11, 2, 20);

/// Verrouille le fichier, le signale, puis le libère 10 ms plus tard.
void _holdLock((String, SendPort) args) {
  final (path, locked) = args;
  final lock = File(path).openSync(mode: FileMode.append)
    ..lockSync(FileLock.exclusive);
  locked.send(null);
  sleep(const Duration(milliseconds: 10));
  lock
    ..unlockSync()
    ..closeSync();
}

const _movie = PlayItem.movie(id: '1', extension: 'mkv', name: 'Mirage');

PlayItem _episode(String id, int season, int episode, {String series = '45'}) =>
    PlayItem.episode(
      id: id,
      extension: 'mkv',
      name: 'Série $series',
      seriesId: series,
      season: season,
      episode: episode,
    );

Progress _progress(
  PlayItem item, {
  int position = 600,
  int duration = 3000,
  bool watched = false,
  bool hidden = false,
  int minutesLater = 0,
}) => Progress(
  item: item,
  position: Duration(seconds: position),
  duration: Duration(seconds: duration),
  watched: watched,
  hidden: hidden,
  updatedAt: _t0.add(Duration(minutes: minutesLater)),
);

void main() {
  test('titres : court pour les affiches, complet pour le lecteur', () {
    expect(_movie.shortTitle, 'Mirage');
    expect(_movie.title, 'Mirage');
    expect(_episode('7', 1, 2).shortTitle, 'Série 45 · S1E2');
    expect(_episode('7', 1, 2).title, 'Série 45 · S1E2');
    const named = PlayItem.episode(
      id: '8',
      extension: 'mkv',
      name: 'Série 45',
      seriesId: '45',
      season: 2,
      episode: 3,
      episodeTitle: 'Le retour',
    );
    expect(named.shortTitle, 'Série 45 · S2E3');
    expect(named.title, 'Série 45 · S2E3 · Le retour');
  });

  test('clé d\'un film ou d\'une série du catalogue', () {
    const movie = CatalogItem(kind: ContentKind.movies, id: '1', name: 'M');
    const series = CatalogItem(kind: ContentKind.series, id: '1', name: 'S');
    expect(movie.libraryKey, _movie.key);
    expect(series.libraryKey, 'series:1');
  });

  group('seuils', () {
    test('reprise proposée après 30 s, pas sur un contenu vu ou fini', () {
      expect(_progress(_movie, position: 29).resumeAt, isNull);
      expect(
        _progress(_movie, position: 30).resumeAt,
        const Duration(seconds: 30),
      );
      expect(
        _progress(_movie, position: 2850, watched: true).resumeAt,
        isNull,
        reason: 'vu et arrêté à la fin',
      );
      expect(
        _progress(_movie, position: 600, watched: true).resumeAt,
        const Duration(seconds: 600),
        reason: 'vu, puis revu en partie : on peut reprendre',
      );
      expect(
        _progress(_movie, position: 2700, duration: 3000).resumeAt,
        isNull,
      );
    });

    test('vu à 90 % ; durée inconnue ou nulle : jamais vu par la position', () {
      expect(
        Progress.reachesEnd(
          const Duration(seconds: 2699),
          const Duration(seconds: 3000),
        ),
        isFalse,
      );
      expect(
        Progress.reachesEnd(
          const Duration(seconds: 2700),
          const Duration(seconds: 3000),
        ),
        isTrue,
      );
      expect(
        Progress.reachesEnd(const Duration(hours: 5), Duration.zero),
        isFalse,
      );
      expect(_progress(_movie, duration: 0).fraction, 0);
      expect(_progress(_movie, position: 1500, duration: 3000).fraction, 0.5);
    });
  });

  group('Continuer à regarder', () {
    test(
      'un film et deux épisodes d\'une série : deux entrées, récentes d\'abord',
      () {
        final library = const Library()
            .withProgress(_progress(_movie, minutesLater: 1))
            .withProgress(_progress(_episode('a', 1, 1), minutesLater: 2))
            .withProgress(_progress(_episode('b', 1, 2), minutesLater: 3));
        final row = library.continueWatching;
        expect(row.map((p) => p.item.key), ['episode:b', 'movie:1']);
      },
    );

    test('une série : son épisode regardé en dernier, quel que soit son '
        'numéro ; fini, il reste pour proposer le suivant', () {
      // Insérés dans le désordre : seul compte l'ordre des dates.
      var library = const Library()
          .withProgress(_progress(_episode('e8', 1, 8), minutesLater: 1))
          .withProgress(_progress(_episode('e5', 1, 5), minutesLater: 3))
          .withProgress(
            _progress(_episode('x', 1, 1, series: '9'), minutesLater: 2),
          );
      expect(library.continueWatching.map((p) => p.item.key), [
        'episode:e5',
        'episode:x',
      ]);

      // E5 abandonné il y a longtemps, puis E8 vu jusqu'au bout : E8 reste,
      // l'accueil propose E9.
      library = library.withProgress(
        _progress(
          _episode('e8', 1, 8),
          position: 2850,
          watched: true,
          minutesLater: 4,
        ),
      );
      expect(library.continueWatching.first.finished, isTrue);

      // E9 lancé puis coupé tout de suite, même déjà vu autrefois : il
      // reste, à reprendre, et n'est pas compté comme fini.
      library = library.withProgress(
        _progress(
          _episode('e9', 1, 9),
          position: 2,
          watched: true,
          minutesLater: 5,
        ),
      );
      expect(library.continueWatching.first.item.key, 'episode:e9');
      expect(library.continueWatching.first.finished, isFalse);
      library = library.withProgress(
        _progress(
          _episode('e9', 1, 9),
          position: 2850,
          watched: true,
          minutesLater: 4,
        ),
      );
      expect(library.continueWatching.map((p) => p.item.key), [
        'episode:e8',
        'episode:x',
      ]);
    });

    test(
      'exclut les films finis ou à peine commencés, les séries retirées',
      () {
        final library = const Library()
            .withProgress(_progress(_movie, position: 2850, watched: true))
            .withProgress(_progress(_episode('a', 1, 1), hidden: true))
            .withProgress(
              _progress(
                const PlayItem.movie(id: '2', extension: 'mkv', name: 'Court'),
                position: 10,
              ),
            );
        expect(library.continueWatching, isEmpty);
      },
    );
  });

  group('library.json', () {
    test('aller-retour JSON, au format de la règle 7', () {
      final library = const Library()
          .withFavorite(
            Favorite(
              key: 'series:45',
              name: 'Les Veilleurs',
              poster: 'https://x/p.jpg',
              addedAt: _t0,
            ),
          )
          .withProgress(_progress(_movie))
          .withProgress(_progress(_episode('789', 2, 3)));
      final json = library.toJson();
      expect(json['version'], 1);
      final episode = (json['progress']! as Map)['episode:789'] as Map;
      expect(episode['seriesId'], '45');
      expect(episode['season'], 2);
      expect(episode['episode'], 3);
      expect(episode['position'], 600);

      final back = Library.fromJson(jsonDecode(jsonEncode(json)));
      expect(back.favorites.keys, ['series:45']);
      expect(back.favorites['series:45']!.isSeries, isTrue);
      expect(back.progress['episode:789']!.item.season, 2);
      expect(back.progress['movie:1']!.position, const Duration(seconds: 600));
    });

    test('entrées illisibles ignorées une à une', () {
      final library = Library.fromJson({
        'version': 1,
        'favorites': {
          'movie:1': {'name': 'A'},
          'autre:2': {'name': 'B'},
          'movie:3': 'x',
        },
        'progress': {
          'movie:1': {'name': 'A'},
          'episode:2': {'name': 'B', 'extension': 'mkv'},
        },
      });
      expect(library.favorites.keys, ['movie:1']);
      expect(
        library.progress,
        isEmpty,
        reason: 'extension, ou série, manquante',
      );
    });
  });

  group('LibraryStore', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('couchplay_library_');
      file = File('${dir.path}/library.json');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('absent ou vide : bibliothèque vide', () {
      expect(LibraryStore(file).load().favorites, isEmpty);
      file.writeAsStringSync('  ');
      expect(LibraryStore(file).load().favorites, isEmpty);
    });

    test('écrit puis relit, sans fichier temporaire restant', () async {
      final library = const Library().withProgress(_progress(_movie));
      await LibraryStore(file).save(library);
      expect(LibraryStore(file).load().progress.keys, ['movie:1']);
      expect(dir.listSync().map((e) => e.uri.pathSegments.last), [
        'library.json',
      ]);
    });

    test('corrompu : mis de côté en .bak, puis bibliothèque vide', () {
      file.writeAsStringSync('{"version":1,"favorites":{');
      expect(LibraryStore(file).load().favorites, isEmpty);
      expect(
        File('${file.path}.bak').readAsStringSync(),
        startsWith('{"version"'),
      );
      expect(file.existsSync(), isFalse);
    });

    test('verrouillé (antivirus, synchronisation) : jamais écrasé', () async {
      file.writeAsStringSync('{"version":1,"favorites":{"movie:1":{}}}');
      final original = file.readAsStringSync();
      final lock = file.openSync(mode: FileMode.append)
        ..lockSync(FileLock.exclusive);
      final store = LibraryStore(file);
      expect(store.load().favorites, isEmpty);
      await store.save(const Library());
      lock
        ..unlockSync()
        ..closeSync();
      // Un verrou n'est pas un fichier illisible : laissé en place, intact.
      expect(File('${file.path}.bak').existsSync(), isFalse);
      expect(file.readAsStringSync(), original);
    }, skip: !Platform.isWindows);

    test(
      'verrou passager (écriture en cours) : relu, pas mis de côté',
      () async {
        await LibraryStore(file)
            .save(const Library().withProgress(_progress(_movie)));
        // Un autre isolate tient le fichier 10 ms, comme le renommage d'une
        // écriture : load() attend sans bloquer l'isolate qui le libère.
        final locked = ReceivePort();
        await Isolate.spawn(_holdLock, (file.path, locked.sendPort));
        await locked.first;
        expect(LibraryStore(file).load().progress.keys, ['movie:1']);
        expect(File('${file.path}.bak').existsSync(), isFalse);
      },
      skip: !Platform.isWindows,
    );

    test('mal encodé : mis de côté aussi, jamais écrasé', () async {
      // UTF-16 avec BOM, comme un fichier réenregistré par un éditeur.
      const bytes = [0xFF, 0xFE, 0x7B, 0x00];
      file.writeAsBytesSync(bytes);
      final store = LibraryStore(file);
      expect(store.load().favorites, isEmpty);
      await store.save(const Library());
      expect(File('${file.path}.bak').readAsBytesSync(), bytes);
    });
  });

  group('historique', () {
    final base = const Library()
        .withProgress(_progress(_movie, minutesLater: 1))
        .withProgress(_progress(_episode('7', 1, 2), minutesLater: 3))
        .withProgress(
          _progress(_episode('8', 1, 3), hidden: true, minutesLater: 2),
        )
        .withProgress(
          _progress(
            const PlayItem.movie(id: '2', extension: 'mkv', name: 'Vu'),
            position: 3000,
            watched: true,
          ),
        );

    test('tout y figure, du plus récent au plus ancien', () {
      expect(base.history.map((p) => p.item.key), [
        'episode:7',
        'episode:8',
        'movie:1',
        'movie:2',
      ]);
      // « Continuer à regarder » ne garde ni le retiré ni le vu (episode:8, movie:2).
      expect(base.continueWatching.map((p) => p.item.key), [
        'episode:7',
        'movie:1',
      ]);
    });

    test('retirer une ligne efface sa progression, pas les autres', () {
      final next = base.withoutProgress('movie:1');
      expect(next.progress.keys, isNot(contains('movie:1')));
      expect(next.progress, hasLength(3));
    });

    test("retirer un épisode change « Continuer » et l'épisode proposé", () {
      final visible = base.withProgress(
        _progress(_episode('8', 1, 3), minutesLater: 2),
      );
      expect(visible.continueWatching.map((p) => p.item.key), [
        'episode:7',
        'movie:1',
      ]);
      final next = visible.withoutProgress('episode:7');
      // L'épisode regardé en dernier devient le précédent.
      expect(next.continueWatching.map((p) => p.item.key), [
        'episode:8',
        'movie:1',
      ]);
    });

    test('effacer vide la progression, les favoris restent', () {
      final next = base
          .withFavorite(Favorite(key: 'movie:1', name: 'Mirage', addedAt: _t0))
          .withoutHistory();
      expect(next.history, isEmpty);
      expect(next.favorites.keys, ['movie:1']);
    });

    test("un library.json écrit avant se relit à l'identique", () {
      final json = {
        'version': 1,
        'favorites': {
          'movie:1': {'name': 'Mirage', 'addedAt': '2026-11-02T20:00:00.000Z'},
        },
        'progress': {
          'movie:1': {
            'name': 'Mirage',
            'extension': 'mkv',
            'position': 600,
            'duration': 3000,
            'watched': false,
            'hidden': false,
            'updatedAt': '2026-11-02T20:00:00.000Z',
          },
        },
      };
      expect(Library.fromJson(json).toJson(), json);
    });
  });
}
