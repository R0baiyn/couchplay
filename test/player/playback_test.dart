import 'package:couchplay/player/playback.dart';
import 'package:couchplay/player/player_controls.dart';
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

  test('formatTime', () {
    expect(formatTime(const Duration(seconds: 9)), '0:09');
    expect(formatTime(const Duration(minutes: 5, seconds: 9)), '5:09');
    expect(
      formatTime(const Duration(hours: 1, minutes: 50, seconds: 30)),
      '1:50:30',
    );
  });
}
