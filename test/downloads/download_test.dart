import 'dart:convert';
import 'dart:io';

import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/downloads/download.dart';
import 'package:couchplay/library/library.dart';
import 'package:couchplay/logging.dart';
import 'package:flutter_test/flutter_test.dart';

const _movie = PlayItem.movie(
  id: '12',
  extension: 'mkv',
  name: 'Mirage',
  poster: 'http://affiches.test/1.jpg',
);
const _episode = PlayItem.episode(
  id: '34',
  extension: 'mp4',
  name: 'Série',
  seriesId: '5',
  season: 2,
  episode: 3,
  episodeTitle: 'Le retour',
);

void main() {
  late Directory root;
  late DownloadsStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('couchplay_dl_');
    store = DownloadsStore(
      File('${root.path}/downloads.json'),
      Directory('${root.path}/videos')..createSync(),
    );
  });
  tearDown(() async {
    // Un chargement qui retire une entrée réécrit le manifeste.
    await SerialFileWriter.flushAll();
    root.deleteSync(recursive: true);
  });

  final date = DateTime.utc(2026, 11, 16, 10);

  test('aller-retour du manifeste, dans l\'ordre d\'ajout', () async {
    final entries = {
      _episode.key: Download(
        item: _episode,
        size: 1000,
        received: 400,
        status: DownloadStatus.failed,
        error: 'Connexion interrompue',
        addedAt: date,
      ),
      _movie.key: Download(item: _movie, addedAt: date),
    };
    await store.save(entries);

    final read = DownloadsStore(store.manifest, store.videos).load();
    expect(read.keys, ['episode:34', 'movie:12']);
    final episode = read['episode:34']!;
    expect(episode.item.seasonEpisode, (2, 3, '5', 'Le retour'));
    expect(
      (episode.size, episode.received, episode.status, episode.error),
      (1000, 400, DownloadStatus.failed, 'Connexion interrompue'),
    );
    expect(read['movie:12']!.item.poster, 'http://affiches.test/1.jpg');
    expect(read['movie:12']!.addedAt, date);
  });

  test('ni URL de flux ni identifiant dans le fichier', () async {
    await store.save({
      _movie.key: Download(item: _movie, addedAt: date),
      _episode.key: Download(item: _episode, addedAt: date),
    });
    final text = store.manifest.readAsStringSync();
    expect(text, isNot(contains('movie/')));
    expect(text, isNot(contains('series/')));
    expect(text, isNot(contains('username')));
    expect(text, isNot(contains('password')));
    final entry = (jsonDecode(text) as Map)['downloads']['movie:12'] as Map;
    expect(entry.keys, {
      'name',
      'poster',
      'extension',
      'size',
      'received',
      'status',
      'addedAt',
    });
  });

  test('entrée illisible ignorée seule, en cours relu en attente', () {
    store.manifest.writeAsStringSync(
      jsonEncode({
        'version': 1,
        'downloads': {
          'movie:1': {'name': 'A', 'extension': 'mkv', 'status': 'running'},
          'movie:2': {'name': 'Sans extension', 'status': 'queued'},
          'movie:3': {'name': 'B', 'extension': 'mkv', 'status': 'inconnu'},
          'movie:../x': {'name': 'C', 'extension': 'mkv', 'status': 'queued'},
          'episode:4': {'name': 'D', 'extension': 'mkv', 'status': 'queued'},
          'movie:5': 'pas un objet',
        },
      }),
    );
    final read = store.load();
    expect(read.keys, ['movie:1']);
    expect(read['movie:1']!.status, DownloadStatus.queued);
  });

  test('fichier illisible ou absent : liste vide', () {
    expect(store.load(), isEmpty);
    store.manifest.writeAsStringSync('{pas du json');
    expect(store.load(), isEmpty);
  });

  test('manifeste corrompu : mis de côté, vidéos gardées', () async {
    store.manifest.writeAsStringSync('{pas du json');
    final video = File('${store.videos.path}/movie-12.mkv')
      ..writeAsStringSync('vidéo');

    expect(store.load(), isEmpty);
    await store.tidy(const []);

    expect(video.existsSync(), isTrue);
    expect(
      File('${store.manifest.path}.bak').readAsStringSync(),
      '{pas du json',
    );
  });

  test('champs du mauvais type : rien ne lève, entrée ignorée', () {
    const weird = <Object?>[
      null,
      true,
      1.5,
      'x',
      [1],
      {'a': 1},
    ];
    const fields = ['name', 'extension', 'status', 'size', 'received'];
    for (final field in [...fields, 'error', 'addedAt', 'seriesId', 'season']) {
      for (final value in weird) {
        store.manifest.writeAsStringSync(
          jsonEncode({
            'version': 1,
            'downloads': {
              'episode:4': {
                'name': 'A',
                'extension': 'mkv',
                'status': 'queued',
                'seriesId': '3',
                'season': 1,
                'episode': 2,
                field: value,
              },
              'movie:1': {'name': 'B', 'extension': 'mkv', 'status': 'queued'},
            },
          }),
        );
        expect(store.load().keys, contains('movie:1'), reason: '$field=$value');
      }
    }
    for (final top in <Object?>[
      [],
      'x',
      {'downloads': []},
    ]) {
      store.manifest.writeAsStringSync(jsonEncode(top));
      expect(store.load(), isEmpty);
    }
  });

  test('manifeste de forme inattendue : mis de côté, vidéos gardées', () async {
    final video = File('${store.videos.path}/movie-12.mkv')
      ..writeAsStringSync('vidéo');
    for (final top in <Object?>[
      [],
      'x',
      {'version': 1},
      {'downloads': []},
    ]) {
      store.manifest.writeAsStringSync(jsonEncode(top));
      final fresh = DownloadsStore(store.manifest, store.videos);
      expect(fresh.load(), isEmpty);
      await fresh.tidy(const []);
      expect(video.existsSync(), isTrue, reason: '$top');
      File('${store.manifest.path}.bak').deleteSync();
    }
  });

  test('manifeste corrompu : vidéos gardées au lancement suivant', () async {
    store.manifest.writeAsStringSync('{pas du json');
    final video = File('${store.videos.path}/movie-12.mkv')
      ..writeAsStringSync('vidéo');
    expect(store.load(), isEmpty);
    await store.tidy(const []);

    // Lancement suivant : nouveau magasin, plus de manifeste, la copie
    // illisible est toujours là.
    final next = DownloadsStore(store.manifest, store.videos);
    expect(next.load(), isEmpty);
    await next.tidy(const []);
    expect(video.existsSync(), isTrue);

    // Une nouvelle liste écrite ensuite ne range pas non plus.
    await next.save({_episode.key: Download(item: _episode, addedAt: date)});
    final third = DownloadsStore(store.manifest, store.videos);
    await third.tidy(third.load().values);
    expect(video.existsSync(), isTrue);
  });

  test('entrée prête dont le fichier a disparu : retirée', () async {
    final ready = Download(
      item: _movie,
      size: 3,
      received: 3,
      status: DownloadStatus.ready,
      addedAt: date,
    );
    final gone = Download(
      item: _episode,
      status: DownloadStatus.ready,
      addedAt: date,
    );
    store.fileOf(ready).writeAsStringSync('abc');
    await store.save({ready.key: ready, gone.key: gone});

    expect(DownloadsStore(store.manifest, store.videos).load().keys, [
      'movie:12',
    ]);
  });

  test(
    'fichier disparu : entrée retirée du manifeste, dite une fois',
    () async {
      final ready = Download(
        item: _movie,
        size: 3,
        received: 3,
        status: DownloadStatus.ready,
        addedAt: date,
      );
      final gone = Download(
        item: _episode,
        status: DownloadStatus.ready,
        addedAt: date,
      );
      store.fileOf(ready).writeAsStringSync('abc');
      await store.save({ready.key: ready, gone.key: gone});
      openJournal(File('${root.path}/couchplay.log'));
      addTearDown(closeJournal);

      DownloadsStore(store.manifest, store.videos).load();
      await SerialFileWriter.flushAll();

      final written = jsonDecode(store.manifest.readAsStringSync()) as Map;
      expect(written['downloads'], {ready.key: ready.toJson()});

      // Lancement suivant : plus rien à dire.
      expect(DownloadsStore(store.manifest, store.videos).load().keys, [
        ready.key,
      ]);
      expect(await readJournalTail(), [
        endsWith('Téléchargement retiré : fichier disparu'),
      ]);
    },
  );

  test('dossier des vidéos absent : manifeste gardé', () async {
    await store.save({
      _movie.key: Download(
        item: _movie,
        status: DownloadStatus.ready,
        addedAt: date,
      ),
    });
    final written = store.manifest.readAsStringSync();
    store.videos.deleteSync();

    expect(DownloadsStore(store.manifest, store.videos).load(), isEmpty);
    await SerialFileWriter.flushAll();

    expect(store.manifest.readAsStringSync(), written);
  });

  test('id ou extension qui sortiraient du dossier : refusés', () {
    expect(isDownloadable(_movie), isTrue);
    for (final item in [
      const PlayItem.movie(id: '../1', extension: 'mkv', name: 'x'),
      const PlayItem.movie(id: '1', extension: 'mkv/..', name: 'x'),
      const PlayItem.movie(id: '', extension: 'mkv', name: 'x'),
    ]) {
      expect(isDownloadable(item), isFalse, reason: item.id);
    }
    expect(fileNameOf(_episode), 'episode-34.mp4');
  });

  test("nom d'affiche : tiré de la clé, jamais de l'URL", () {
    expect(posterNameOf(_movie), 'poster-movie-12');
    expect(posterNameOf(_episode), 'poster-series-5');
    // Id de série qui sortirait du dossier : une affiche par épisode.
    const odd = PlayItem.episode(
      id: '34',
      extension: 'mp4',
      name: 'x',
      seriesId: '../5',
      season: 1,
      episode: 1,
    );
    expect(posterNameOf(odd), 'poster-episode-34');
  });

  test('rangement : seuls les fichiers des entrées restent', () async {
    final keep = Download(item: _movie, addedAt: date);
    store.partOf(keep).writeAsStringSync('a');
    File('${store.videos.path}/movie-99.mkv').writeAsStringSync('b');
    File('${store.videos.path}/movie-99.mkv.part').writeAsStringSync('c');
    await store.writePoster(keep, [1, 2]);
    File('${store.videos.path}/poster-movie-99').writeAsStringSync('d');
    File('${store.videos.path}/poster-movie-12.part').writeAsStringSync('e');

    await store.tidy([keep]);

    expect(
      store.videos.listSync().map((e) => e.uri.pathSegments.last),
      unorderedEquals(['movie-12.mkv.part', 'poster-movie-12']),
    );
  });
}

extension on PlayItem {
  (int?, int?, String?, String?) get seasonEpisode =>
      (season, episode, seriesId, episodeTitle);
}
