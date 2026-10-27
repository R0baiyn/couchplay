import 'dart:convert';
import 'dart:io';

import 'package:couchplay/library/library.dart';
import 'package:couchplay/library/library_store.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 11, 2, 20);

const _movie = PlayItem.movie(id: '1', extension: 'mkv', name: 'Inception');

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
  group('seuils', () {
    test('reprise proposée après 30 s, pas sur un contenu vu ou fini', () {
      expect(_progress(_movie, position: 29).resumeAt, isNull);
      expect(
        _progress(_movie, position: 30).resumeAt,
        const Duration(seconds: 30),
      );
      expect(_progress(_movie, position: 600, watched: true).resumeAt, isNull);
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

    test('exclut les contenus vus, retirés ou à peine commencés', () {
      final library = const Library()
          .withProgress(_progress(_movie, watched: true))
          .withProgress(_progress(_episode('a', 1, 1), hidden: true))
          .withProgress(
            _progress(_episode('x', 1, 1, series: '9'), position: 10),
          );
      expect(library.continueWatching, isEmpty);
    });
  });

  group('library.json', () {
    test('aller-retour JSON, au format de la règle 7', () {
      final library = const Library()
          .withFavorite(
            Favorite(
              key: 'series:45',
              name: 'Vikings',
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
  });
}
