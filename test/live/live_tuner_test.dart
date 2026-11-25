import 'dart:async';

import 'package:couchplay/live/channel.dart';
import 'package:couchplay/live/live_tuner.dart';
import 'package:couchplay/player/playback.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

Channel _channel(int i) => Channel(id: '${9001 + i}', name: 'Chaîne $i');

void main() {
  final twelve = [for (var i = 0; i < 12; i++) _channel(i)];

  /// Chaînes ouvertes, dans l'ordre ; chaque ouverture réussit tout de suite,
  /// sauf si [fail] lève pour elle.
  late List<String> opened;
  late List<String> watched;
  Object? Function(Channel)? fail;

  setUp(() {
    opened = [];
    watched = [];
    fail = null;
  });

  LiveTuner tuner(List<Channel> channels, Channel start) => LiveTuner(
    channels: channels,
    start: start,
    open: (channel, _) async {
      opened.add(channel.id);
      if (fail?.call(channel) case final Object error) throw error;
    },
    onWatched: (channel) => watched.add(channel.id),
  )..start();

  group('zapping', () {
    test('ouverture : la chaîne choisie, tout de suite', () {
      fakeAsync((async) {
        final t = tuner(twelve, twelve[3]);
        async.flushMicrotasks();
        expect(opened, ['9004']);
        expect(watched, ['9004']);
        expect(t.channel.id, '9004');
        expect(t.opening, isFalse);
        expect(t.error, isNull);
      });
    });

    test(
      'un appui : bandeau changé aussitôt, flux ouvert après l\'attente',
      () {
        fakeAsync((async) {
          final t = tuner(twelve, twelve[0]);
          async.flushMicrotasks();
          t.zap(1);
          expect(t.channel.id, '9002');
          async.elapse(LiveTuner.zapDelay - const Duration(milliseconds: 1));
          expect(opened, ['9001']);
          async.elapse(const Duration(milliseconds: 1));
          expect(opened, ['9001', '9002']);
        });
      },
    );

    test('dix appuis rapides : une seule ouverture, vers la 10e suivante', () {
      fakeAsync((async) {
        final t = tuner(twelve, twelve[0]);
        async.flushMicrotasks();
        for (var i = 0; i < 10; i++) {
          t.zap(1);
          async.elapse(const Duration(milliseconds: 100));
        }
        expect(t.channel.id, '9011');
        async.elapse(const Duration(seconds: 5));
        expect(opened, ['9001', '9011']);
      });
    });

    test('on boucle aux deux bouts de la liste', () {
      fakeAsync((async) {
        final t = tuner(twelve, twelve[0]);
        async.flushMicrotasks();
        t.zap(-1);
        expect(t.channel.id, '9012');
        t.zap(1);
        expect(t.channel.id, '9001');
        t.zap(1);
        async.elapse(const Duration(seconds: 1));
        expect(opened, ['9001', '9002']);
      });
    });

    test(
      'retour sur la chaîne en cours pendant l\'attente : rien à rouvrir',
      () {
        fakeAsync((async) {
          final t = tuner(twelve, twelve[0]);
          async.flushMicrotasks();
          t
            ..zap(1)
            ..zap(-1);
          async.elapse(const Duration(seconds: 5));
          expect(opened, ['9001']);
        });
      },
    );

    test('liste d\'une seule chaîne : le zapping ne fait rien', () {
      fakeAsync((async) {
        final t = tuner([twelve[0]], twelve[0]);
        async.flushMicrotasks();
        t.zap(1);
        expect(t.channel.id, '9001');
        async.elapse(const Duration(seconds: 5));
        expect(opened, ['9001']);
      });
    });

    test('liste vide : la chaîne choisie seule, le zapping ne fait rien', () {
      fakeAsync((async) {
        final t = tuner(const [], twelve[4]);
        async.flushMicrotasks();
        t
          ..zap(1)
          ..zap(-1);
        expect(t.channel.id, '9005');
        async.elapse(const Duration(seconds: 5));
        expect(opened, ['9005']);
      });
    });

    test('zapping pendant une ouverture : seule la dernière compte', () {
      fakeAsync((async) {
        final first = Completer<void>();
        final t = LiveTuner(
          channels: twelve,
          start: twelve[0],
          open: (channel, _) {
            opened.add(channel.id);
            // La 1re ouverture finit en échec après la 2e : son message ne
            // doit pas s'afficher.
            return channel.id == '9001' ? first.future : Future.value();
          },
          onWatched: (channel) => watched.add(channel.id),
        )..start();
        t.zap(1);
        async.elapse(LiveTuner.zapDelay);
        expect(opened, ['9001', '9002']);
        first.completeError(const PlaybackFailed());
        async.flushMicrotasks();
        expect(t.error, isNull);
        expect(t.opening, isFalse);
        expect(watched, ['9002']);
      });
    });

    test('une ouverture abandonnée car remplacée ne dit rien', () {
      fakeAsync((async) {
        final first = Completer<void>();
        final t = LiveTuner(
          channels: twelve,
          start: twelve[0],
          open: (channel, _) {
            opened.add(channel.id);
            return channel.id == '9001' ? first.future : Future.value();
          },
          onWatched: (channel) => watched.add(channel.id),
        )..start();
        t.zap(1);
        async.elapse(LiveTuner.zapDelay);
        first.completeError(const PlaybackAbandoned());
        async.flushMicrotasks();
        expect(t.error, isNull);
        expect(watched, ['9002']);
      });
    });
  });

  group('course au zapping (adresse lente à résoudre)', () {
    /// Comme l'écran : résout l'adresse (lente, [requests]), puis n'ouvre le
    /// flux que si l'ouverture est encore la bonne.
    LiveTuner slow(Map<String, Completer<void>> requests) => LiveTuner(
      channels: twelve,
      start: twelve[0],
      open: (channel, current) async {
        await requests[channel.id]!.future;
        if (!current()) throw const PlaybackAbandoned();
        opened.add(channel.id);
      },
      onWatched: (channel) => watched.add(channel.id),
    )..start();

    test('A lente, zapping sur B : B ouvert en dernier, A jamais', () {
      fakeAsync((async) {
        final requests = {'9001': Completer<void>(), '9002': Completer<void>()};
        final t = slow(requests);
        t.zap(1);
        async.elapse(LiveTuner.zapDelay);
        requests['9002']!.complete();
        async.flushMicrotasks();
        requests['9001']!.complete();
        async.flushMicrotasks();

        expect(opened, ['9002']);
        expect(watched, ['9002']);
        expect(t.channel.id, '9002');
        expect(t.opening, isFalse);
        expect(t.error, isNull);
      });
    });

    test('A lente, B encore en cours : A ne s\'ouvre pas, B finit', () {
      fakeAsync((async) {
        final requests = {'9001': Completer<void>(), '9002': Completer<void>()};
        final t = slow(requests);
        t.zap(1);
        async.elapse(LiveTuner.zapDelay);
        requests['9001']!.complete();
        async.flushMicrotasks();
        expect(opened, isEmpty);
        expect(t.opening, isTrue);
        requests['9002']!.complete();
        async.flushMicrotasks();

        expect(opened, ['9002']);
        expect(t.opening, isFalse);
      });
    });

    test('ouverture courante abandonnée (lecteur pris ailleurs) : pas de '
        'roue sans fin, message et « Réessayer »', () {
      fakeAsync((async) {
        fail = (_) => const PlaybackAbandoned();
        final t = tuner(twelve, twelve[0]);
        async.flushMicrotasks();

        expect(t.opening, isFalse);
        expect(t.error, const PlaybackFailed().message);
        fail = null;
        t.retry();
        async.flushMicrotasks();
        expect(t.error, isNull);
        expect(opened, ['9001', '9001']);
      });
    });
  });

  group('reconnexion', () {
    test('coupure : une nouvelle ouverture de la même chaîne après 1 s', () {
      fakeAsync((async) {
        final t = tuner(twelve, twelve[2]);
        async.flushMicrotasks();
        t.lost();
        expect(t.opening, isTrue);
        async.elapse(const Duration(milliseconds: 999));
        expect(opened, ['9003']);
        async.elapse(const Duration(milliseconds: 1));
        expect(opened, ['9003', '9003']);
        expect(t.opening, isFalse);
        expect(t.error, isNull);
      });
    });

    test('2e coupure : message clair, plus aucun essai', () {
      fakeAsync((async) {
        final t = tuner(twelve, twelve[2]);
        async.flushMicrotasks();
        t.lost();
        async.elapse(const Duration(seconds: 1));
        // Le flux repris tient longtemps : le droit à une reconnexion ne
        // revient pas pour autant (sinon une coupure toutes les 15 s boucle).
        async.elapse(const Duration(minutes: 10));
        t.lost();
        async.elapse(const Duration(minutes: 1));
        expect(opened, ['9003', '9003']);
        expect(t.opening, isFalse);
        expect(t.error, LiveTuner.lostMessage);
      });
    });

    test('refus du serveur : son message, aucun nouvel essai', () {
      fakeAsync((async) {
        fail = (_) => const PlaybackFailed();
        final t = tuner(twelve, twelve[0]);
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        expect(opened, ['9001']);
        expect(t.error, const PlaybackFailed().message);
        expect(watched, isEmpty);
        // Une fin de flux signalée après l'échec ne relance rien.
        t.lost();
        async.elapse(const Duration(minutes: 1));
        expect(opened, ['9001']);
      });
    });

    test('refus à la reconnexion : son message, aucun autre essai', () {
      fakeAsync((async) {
        final t = tuner(twelve, twelve[0]);
        async.flushMicrotasks();
        fail = (_) => const PlaybackFailed();
        t.lost();
        async.elapse(const Duration(minutes: 1));
        expect(opened, ['9001', '9001']);
        expect(t.error, const PlaybackFailed().message);
      });
    });

    test('zapping pendant l\'attente : l\'attente est annulée', () {
      fakeAsync((async) {
        final t = tuner(twelve, twelve[0]);
        async.flushMicrotasks();
        t
          ..lost()
          ..zap(1);
        async.elapse(const Duration(seconds: 5));
        expect(opened, ['9001', '9002']);
        expect(t.opening, isFalse);
      });
    });

    test(
      'zapping : la chaîne suivante a de nouveau droit à une reconnexion',
      () {
        fakeAsync((async) {
          final t = tuner(twelve, twelve[0]);
          async.flushMicrotasks();
          t.lost();
          async.elapse(const Duration(seconds: 1));
          t.zap(1);
          async.elapse(LiveTuner.zapDelay);
          t.lost();
          async.elapse(const Duration(seconds: 1));
          expect(opened, ['9001', '9001', '9002', '9002']);
          expect(t.error, isNull);
        });
      },
    );

    test(
      '« Réessayer » rouvre la chaîne et rend le droit à une reconnexion',
      () {
        fakeAsync((async) {
          final t = tuner(twelve, twelve[0]);
          async.flushMicrotasks();
          t.lost();
          async.elapse(const Duration(seconds: 1));
          t.lost();
          expect(t.error, LiveTuner.lostMessage);
          t.retry();
          async.flushMicrotasks();
          expect(t.error, isNull);
          t.lost();
          async.elapse(const Duration(seconds: 1));
          expect(opened, ['9001', '9001', '9001', '9001']);
          expect(t.error, isNull);
        });
      },
    );

    test('fin de flux pendant une ouverture ou une attente : ignorée', () {
      fakeAsync((async) {
        final pending = Completer<void>();
        final t = LiveTuner(
          channels: twelve,
          start: twelve[0],
          open: (channel, _) {
            opened.add(channel.id);
            return pending.future;
          },
        )..start();
        t.lost();
        async.elapse(const Duration(seconds: 5));
        expect(opened, ['9001']);
        pending.complete();
        async.flushMicrotasks();
        t.zap(1);
        // L'ancien flux finit pendant l'attente du zapping.
        t.lost();
        async.elapse(const Duration(seconds: 5));
        expect(opened, ['9001', '9002']);
      });
    });

    test('arrêté (app en arrière-plan) : ni zapping ni reconnexion en '
        'attente ne rouvrent', () {
      fakeAsync((async) {
        final t = tuner(twelve, twelve[0]);
        async.flushMicrotasks();
        t
          ..lost()
          ..zap(1)
          ..stop();
        async.elapse(const Duration(seconds: 5));
        t.retry();
        async.elapse(const Duration(seconds: 5));
        expect(opened, ['9001']);
        t.dispose();
      });
    });

    test('fermé : plus rien ne s\'ouvre', () {
      fakeAsync((async) {
        final t = tuner(twelve, twelve[0]);
        async.flushMicrotasks();
        t
          ..lost()
          ..dispose();
        async.elapse(const Duration(seconds: 5));
        expect(opened, ['9001']);
      });
    });
  });

  group('bandeau et barres', () {
    test('bandeau : à l\'ouverture et à chaque zapping, puis masqué', () {
      fakeAsync((async) {
        final t = tuner(twelve, twelve[0]);
        expect(t.banner.visible, isTrue);
        async.elapse(LiveTuner.bannerFor);
        expect(t.banner.visible, isFalse);
        t.zap(1);
        expect(t.banner.visible, isTrue);
        async.elapse(LiveTuner.bannerFor - const Duration(seconds: 1));
        t.zap(1);
        async.elapse(LiveTuner.bannerFor - const Duration(seconds: 1));
        expect(t.banner.visible, isTrue, reason: 'relancé par le 2e appui');
        async.elapse(const Duration(seconds: 1));
        expect(t.banner.visible, isFalse);
      });
    });

    test('barres : masquées après le délai, sauf sous la souris', () {
      fakeAsync((async) {
        final bars = AutoHide(const Duration(seconds: 3))..show();
        async.elapse(const Duration(seconds: 3));
        expect(bars.visible, isFalse);
        bars
          ..show()
          ..hold = true;
        async.elapse(const Duration(seconds: 10));
        expect(bars.visible, isTrue);
        bars.hold = false;
        async.elapse(const Duration(seconds: 3));
        expect(bars.visible, isFalse);
        bars
          ..show()
          ..hide();
        expect(bars.visible, isFalse);
      });
    });
  });
}
