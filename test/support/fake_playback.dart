import 'dart:async';

import 'package:couchplay/player/playback.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Lecteur sans libmpv : chaque `open` est noté et démarre aussitôt (durée
/// connue au tour suivant), sauf avec [refuse] (refus http du serveur).
/// [cut] simule la fin du flux (coupure).
final class FakePlayer implements Player {
  /// Médias ouverts, dans l'ordre.
  final opened = <Media>[];

  /// Appels à `stop`, ouvertures comprises (`Playback.open` ferme d'abord).
  var stops = 0;

  /// Le serveur refuse chaque flux (403).
  var refuse = false;

  final _streams = FakePlayerStream();

  @override
  PlayerStream get stream => _streams;

  @override
  final state = const PlayerState();

  @override
  PlatformPlayer? get platform => null;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add(playable as Media);
    // Deux microtâches plus loin : `Playback` a fini d'attendre `open` et
    // écoute le démarrage.
    scheduleMicrotask(
      () => scheduleMicrotask(
        () => refuse
            ? _streams.errors.add('stream: HTTP error 403 Forbidden')
            : _streams.durations.add(const Duration(seconds: 2)),
      ),
    );
  }

  @override
  Future<void> stop() async => stops++;

  /// Fin du flux en cours.
  void cut() => _streams.completions.add(true);

  /// Adresses ouvertes.
  List<String> get urls => [for (final media in opened) media.uri];

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// Flux du lecteur : ceux que `Playback` écoute se commandent, les autres
/// sont vides.
final class FakePlayerStream implements PlayerStream {
  final durations = StreamController<Duration>.broadcast();
  final completions = StreamController<bool>.broadcast();
  final errors = StreamController<String>.broadcast();

  @override
  Stream<Duration> get duration => durations.stream;
  @override
  Stream<bool> get completed => completions.stream;
  @override
  Stream<String> get error => errors.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => const Stream<Never>.empty();
}

/// Contrôleur sans rendu : la vue vidéo reste vide.
final class FakeVideoController implements VideoController {
  FakeVideoController(this.player);

  @override
  final Player player;
  @override
  final notifier = ValueNotifier<PlatformVideoController?>(null);
  @override
  final id = ValueNotifier<int?>(null);
  @override
  final rect = ValueNotifier<Rect?>(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// `Playback` réel (un seul flux, fermer avant d'ouvrir) sur [FakePlayer].
Playback fakePlayback(FakePlayer player) =>
    Playback.withPlayer(player, FakeVideoController(player));
