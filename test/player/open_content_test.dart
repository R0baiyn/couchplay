import 'dart:io';

import 'package:couchplay/library/library.dart';
import 'package:couchplay/player/player_screen.dart';
import 'package:couchplay/player/playback.dart';
import 'package:flutter_test/flutter_test.dart';

/// Journal de ce que [openContent] demande, dans l'ordre.
final class _Calls {
  final events = <String>[];
  final opened = <PlayRequest>[];

  /// Résultat de chaque ouverture, dans l'ordre ; ensuite, réussite.
  final failures = <PlaybackFailed?>[];
  var downloading = false;
  var streamCalls = 0;

  Future<PlaySource?> run(File? file, {PlayRequest? stream}) => openContent(
    file: file,
    local: (file) => localRequest(_movie, file, start: _start),
    stream: () async {
      streamCalls++;
      events.add('stream');
      return stream;
    },
    open: (request) async {
      opened.add(request);
      events.add('open ${request.url.scheme}');
      if (failures.isNotEmpty) {
        if (failures.removeAt(0) case final failure?) throw failure;
      }
    },
    dropFile: () async => events.add('drop'),
    streaming: (open) => events.add('streaming $open'),
    downloading: () => downloading,
    pauseDownloads: () => events.add('pause'),
  );
}

const _movie = PlayItem.movie(id: '12', extension: 'mkv', name: 'Film');
const _start = Duration(minutes: 3);

final _streamRequest = PlayRequest(
  title: 'Film',
  url: Uri.parse('http://serveur.test/x/12.mkv'),
  userAgent: 'ua',
);

void main() {
  late Directory dir;
  late File video;
  late _Calls calls;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('open_content');
    video = File('${dir.path}${Platform.pathSeparator}movie-12.mkv');
    await video.writeAsString('vidéo');
    calls = _Calls();
  });

  tearDown(() => dir.delete(recursive: true));

  test('fichier prêt : lu en local, sans le serveur ni pause', () async {
    calls.downloading = true;
    final source = await calls.run(video, stream: _streamRequest);
    expect(source, PlaySource.local);
    // Ni client, ni résolution du nom : tout passe par `stream`.
    expect(calls.streamCalls, 0);
    expect(calls.events, ['open file', 'streaming false']);
    final request = calls.opened.single;
    expect(request.url.toFilePath(), video.path);
    expect(request.secrets, isEmpty);
    expect(request.headers, isEmpty);
    expect(request.start, _start);
  });

  test('lecture locale : mêmes pistes et même reprise que le flux', () {
    final local = localRequest(
      _movie,
      video,
      audioLanguage: 'eng',
      subtitleLanguage: 'fre',
      start: _start,
    );
    final stream = PlayRequest(
      title: 'Film',
      url: Uri.parse('http://serveur.test/x/12.mkv'),
      userAgent: 'ua',
      audioLanguage: 'eng',
      subtitleLanguage: 'fre',
      start: _start,
    );
    expect(trackProperties(local), trackProperties(stream));
    expect(trackProperties(local), {
      'alang': 'eng',
      'aid': 'auto',
      'slang': 'fre',
      'sid': 'auto',
    });
    expect(local.start, _start);
    expect(local.title, 'Film');
  });

  test('épisode suivant téléchargé : lu en local', () async {
    const next = PlayItem.episode(
      id: '34',
      extension: 'mp4',
      name: 'Série',
      seriesId: '7',
      season: 1,
      episode: 2,
    );
    final file = File('${dir.path}${Platform.pathSeparator}episode-34.mp4');
    await file.writeAsString('vidéo');
    final source = await openContent(
      file: file,
      local: (file) => localRequest(next, file, audioLanguage: 'fre'),
      stream: () => fail('le serveur ne doit pas être appelé'),
      open: (request) async => calls.opened.add(request),
      dropFile: () => fail('rien à retirer'),
      streaming: (_) {},
      downloading: () => false,
      pauseDownloads: () => fail('rien à mettre en pause'),
    );
    expect(source, PlaySource.local);
    expect(calls.opened.single.url.toFilePath(), file.path);
    expect(calls.opened.single.audioLanguage, 'fre');
  });

  test('fichier absent : entrée retirée, puis le flux', () async {
    await video.delete();
    final source = await calls.run(video, stream: _streamRequest);
    expect(source, PlaySource.stream);
    expect(calls.events, ['drop', 'stream', 'streaming true', 'open http']);
  });

  test('fichier illisible : le flux, puis entrée retirée', () async {
    calls.failures.add(const PlaybackFailed());
    final source = await calls.run(video, stream: _streamRequest);
    expect(source, PlaySource.stream);
    expect(calls.events, [
      'open file',
      'stream',
      'streaming true',
      'open http',
      'drop',
    ]);
  });

  test('fichier illisible et serveur injoignable : fichier gardé', () async {
    calls.failures.addAll([
      const PlaybackFailed(),
      const PlaybackFailed(network: true),
    ]);
    await expectLater(
      calls.run(video, stream: _streamRequest),
      throwsA(isA<PlaybackFailed>().having((e) => e.network, 'network', true)),
    );
    expect(calls.events, isNot(contains('drop')));
  });

  test('pas de fichier : le flux, sans pause', () async {
    calls.downloading = true;
    final source = await calls.run(null, stream: _streamRequest);
    expect(source, PlaySource.stream);
    expect(calls.events, ['stream', 'streaming true', 'open http']);
  });

  test('sans compte : rien n\'est ouvert', () async {
    expect(await calls.run(null), isNull);
    expect(calls.opened, isEmpty);
  });

  group('refus du serveur (D-036)', () {
    test(
      'pendant un téléchargement : pause, puis nouvelle ouverture',
      () async {
        calls
          ..downloading = true
          ..failures.add(const PlaybackFailed());
        final source = await calls.run(null, stream: _streamRequest);
        expect(source, PlaySource.stream);
        expect(calls.events, [
          'stream',
          'streaming true',
          'open http',
          'pause',
          'open http',
        ]);
      },
    );

    test('une seule nouvelle ouverture', () async {
      calls
        ..downloading = true
        ..failures.addAll([const PlaybackFailed(), const PlaybackFailed()]);
      await expectLater(
        calls.run(null, stream: _streamRequest),
        throwsA(isA<PlaybackFailed>()),
      );
      expect(calls.events.where((e) => e == 'open http'), hasLength(2));
    });

    test('sans téléchargement : l\'erreur remonte, rien en pause', () async {
      calls.failures.add(const PlaybackFailed());
      await expectLater(
        calls.run(null, stream: _streamRequest),
        throwsA(isA<PlaybackFailed>()),
      );
      expect(calls.events, isNot(contains('pause')));
    });

    for (final failure in [
      const PlaybackFailed(network: true),
      const PlaybackFailed(unreadable: true),
    ]) {
      test('réseau ou format (${failure.message}) : pas de pause', () async {
        calls
          ..downloading = true
          ..failures.add(failure);
        await expectLater(
          calls.run(null, stream: _streamRequest),
          throwsA(isA<PlaybackFailed>()),
        );
        expect(calls.events, isNot(contains('pause')));
      });
    }
  });
}
