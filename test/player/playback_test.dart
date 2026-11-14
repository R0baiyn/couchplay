import 'package:couchplay/player/player_screen.dart';
import 'package:couchplay/player/player_tracks.dart';
import 'package:couchplay/player/playback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('withRetries', () {
    late List<Duration> slept;
    Future<void> sleep(Duration d) async => slept.add(d);

    setUp(() => slept = []);

    test('réussite du premier coup : aucune attente', () async {
      var calls = 0;
      final result = await withRetries(() async {
        calls++;
        return 'ok';
      }, sleep: sleep);
      expect(result, 'ok');
      expect(calls, 1);
      expect(slept, isEmpty);
    });

    test('échec puis réussite : une attente de 1 s', () async {
      var calls = 0;
      await withRetries(() async {
        if (++calls == 1) throw const PlaybackFailed();
      }, sleep: sleep);
      expect(calls, 2);
      expect(slept, [const Duration(seconds: 1)]);
    });

    test('trois échecs : deux nouvelles tentatives, puis l\'erreur', () async {
      var calls = 0;
      await expectLater(
        withRetries(() async {
          calls++;
          throw const PlaybackFailed();
        }, sleep: sleep),
        throwsA(isA<PlaybackFailed>()),
      );
      expect(calls, 3);
      expect(slept, [const Duration(seconds: 1), const Duration(seconds: 1)]);
    });
  });

  test('message clair quand le serveur refuse', () {
    expect(
      const PlaybackFailed().message,
      contains('un autre appareil utilise peut-être ton abonnement'),
    );
  });

  test('coupure ou délai dépassé : message réseau, pas un refus', () {
    for (final cut in [
      'ffmpeg: tcp: Connection timed out',
      'ffmpeg: tcp: Connection refused',
      'stream: Network is unreachable',
      'ffmpeg: Connection reset by peer',
    ]) {
      expect(PlaybackFailed.fromMpv(cut).network, isTrue, reason: cut);
    }
    const timeout = PlaybackFailed(network: true);
    expect(timeout.message, isNot(const PlaybackFailed().message));
    expect(timeout.message, contains('connexion'));
    expect(timeout.message, isNot(contains('abonnement')));
    for (final refused in [
      'stream: HTTP error 403 Forbidden',
      'ffmpeg: Server returned 5XX Server Error reply',
    ]) {
      expect(PlaybackFailed.fromMpv(refused).network, isFalse, reason: refused);
    }
  });

  test('serveur arrêté, textes réels de libmpv sous Windows', () {
    // Relevés avec la libmpv livrée : connexion refusée sur un port fermé,
    // puis réponse 403 (seul « Failed to open » arrive au niveau error).
    const host = '127.0.0.1';
    final stopped = [
      'ffmpeg: tcp: Connection to tcp://$host:1 failed: '
          'Error number -138 occurred',
      'tcp: Connection to tcp://$host:1 failed: Error number -138 occurred',
    ];
    for (final reason in stopped) {
      final failed = PlaybackFailed.fromMpv(reason);
      expect(failed.network, isTrue, reason: reason);
      expect(failed.message, isNot(contains('abonnement')));
    }
    final refused = PlaybackFailed.fromMpv(
      'stream: Failed to open http://$host:8080/movie/***/***/1.mkv.',
    );
    expect(refused.network, isFalse);
    expect(refused.message, contains('abonnement'));
  });

  test('vidéo illisible : autre message, pas de nouvel essai', () async {
    // Message réel de mpv sur Android pour une vidéo en 4:4:4.
    final unreadable = PlaybackFailed.fromMpv('Could not open codec.');
    expect(unreadable.unreadable, isTrue);
    expect(unreadable.message, contains('ne peut pas être lue'));
    for (final refused in [
      'stream: HTTP error 403 Forbidden',
      'ffmpeg: tcp: Connection refused',
      'demux: Failed to open http://***/movie/***/***/1.mkv',
    ]) {
      expect(
        PlaybackFailed.fromMpv(refused).unreadable,
        isFalse,
        reason: refused,
      );
    }

    var calls = 0;
    await expectLater(
      withRetries(() async {
        calls++;
        throw unreadable;
      }, sleep: (_) async {}),
      throwsA(same(unreadable)),
    );
    expect(calls, 1);
  });

  group('trackLabel', () {
    test('langue traduite, titre et codec', () {
      expect(
        trackLabel(index: 0, language: 'fre', title: 'VFF AD', codec: 'ac3'),
        'Français · VFF AD (ac3)',
      );
      expect(trackLabel(index: 0, language: 'eng'), 'Anglais');
      expect(trackLabel(index: 0, language: 'chi'), 'chi');
    });

    test('piste sans informations : « Piste n »', () {
      expect(trackLabel(index: 2), 'Piste 3');
      expect(trackLabel(index: 0, codec: 'subrip'), 'Piste 1 (subrip)');
    });
  });

  test('un abandon ne relance pas d\'essai', () async {
    var calls = 0;
    await expectLater(
      withRetries(() async {
        calls++;
        throw const PlaybackAbandoned();
      }, sleep: (_) async {}),
      throwsA(isA<PlaybackAbandoned>()),
    );
    expect(calls, 1);
  });

  group('trackProperties', () {
    const url = 'http://serveur.test/f.mkv';

    test('par défaut : audio français, pas de sous-titres', () {
      final request = PlayRequest(
        title: 't',
        url: Uri.parse(url),
        userAgent: 'u',
      );
      expect(trackProperties(request), {
        'alang': 'fr,fre,fra,fr-FR',
        'aid': 'auto',
        'sid': 'no',
      });
    });

    test('langues de l\'épisode précédent gardées', () {
      final request = PlayRequest(
        title: 't',
        url: Uri.parse(url),
        userAgent: 'u',
        audioLanguage: 'eng',
        subtitleLanguage: 'fre',
      );
      expect(trackProperties(request), {
        'alang': 'eng',
        'aid': 'auto',
        'slang': 'fre',
        'sid': 'auto',
      });
    });
  });

  test('isStreamFailure : erreurs du flux seulement', () {
    expect(isStreamFailure('error', 'stream'), isTrue);
    expect(isStreamFailure('error', 'ffmpeg'), isTrue);
    expect(isStreamFailure('error', 'demux'), isTrue);
    expect(isStreamFailure('warn', 'stream'), isFalse);
    expect(isStreamFailure('error', 'vo'), isFalse);
  });

  test('endedEarly : coupé plus de 30 s avant la fin', () {
    const minute = Duration(minutes: 1);
    expect(endedEarly(const Duration(seconds: 10), minute), isTrue);
    expect(endedEarly(const Duration(seconds: 30), minute), isFalse);
    expect(endedEarly(minute, minute), isFalse);
    expect(endedEarly(const Duration(seconds: 10), Duration.zero), isFalse);
  });
}
