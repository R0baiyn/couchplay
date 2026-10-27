import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../logging.dart';

/// Ce que le lecteur doit ouvrir.
final class PlayRequest {
  const PlayRequest({
    required this.title,
    required this.url,
    required this.userAgent,
    this.secrets = const [],
  });

  final String title;

  /// Porte les identifiants dans son chemin : jamais loggée sans masquage.
  final Uri url;
  final String userAgent;

  /// Identifiants du compte, masqués dans tout message du lecteur.
  final List<String> secrets;
}

/// Le flux n'a pas pu démarrer, nouvelles tentatives comprises.
final class PlaybackFailed implements Exception {
  const PlaybackFailed();

  String get message =>
      'Le serveur refuse la connexion : un autre appareil utilise peut-être '
      'ton abonnement.';

  @override
  String toString() => message;
}

/// Lance [attempt] ; en cas d'échec, réessaie après [delay], au plus
/// [retries] fois. La dernière erreur remonte.
Future<T> withRetries<T>(
  Future<T> Function() attempt, {
  int retries = 2,
  Duration delay = const Duration(seconds: 1),
  Future<void> Function(Duration) sleep = Future<void>.delayed,
}) async {
  for (var tried = 0; ; tried++) {
    try {
      return await attempt();
    } on Exception {
      if (tried >= retries) rethrow;
      await sleep(delay);
    }
  }
}

/// Seul propriétaire du lecteur de l'app (règle 3) : un seul flux à la fois.
/// Ouvrir un flux remplace le précédent, qui est fermé d'abord.
final class Playback {
  Playback()
    : player = Player(
        configuration: const PlayerConfiguration(
          title: 'CouchPlay',
          logLevel: MPVLogLevel.error,
        ),
      ) {
    controller = VideoController(player);
  }

  final Player player;
  late final VideoController controller;

  /// Délai maximal pour que le flux démarre (en-têtes reçus, durée connue).
  static const startTimeout = Duration(seconds: 20);

  var _generation = 0;

  /// Ouvre [request] ; lève [PlaybackFailed] si le flux ne démarre pas
  /// après les nouvelles tentatives (refus du serveur, réseau coupé…).
  Future<void> open(PlayRequest request) async {
    final generation = ++_generation;
    await player.stop();
    await _defaultTracks();
    final media = Media(
      request.url.toString(),
      httpHeaders: {'User-Agent': request.userAgent},
    );
    try {
      await withRetries(() async {
        // Une ouverture plus récente a pris la main : on abandonne celle-ci.
        if (generation != _generation) return;
        await _start(media, request.secrets);
      });
    } on Exception {
      if (generation == _generation) throw const PlaybackFailed();
    }
  }

  /// Piste audio française si elle existe, sous-titres désactivés : les
  /// fichiers marquent souvent une piste anglaise « par défaut ». Remis à
  /// chaque ouverture, sinon le choix fait sur un film suivrait au suivant.
  Future<void> _defaultTracks() async {
    final native = player.platform;
    if (native is! NativePlayer) return;
    await native.setProperty('alang', 'fr,fre,fra,fr-FR');
    await native.setProperty('aid', 'auto');
    await native.setProperty('sid', 'no');
  }

  Future<void> _start(Media media, List<String> secrets) async {
    final done = Completer<void>();
    final subscriptions = [
      player.stream.duration.listen((duration) {
        if (duration > Duration.zero && !done.isCompleted) done.complete();
      }),
      player.stream.error.listen((error) {
        // Le message de mpv recopie souvent l'URL, identifiants compris.
        log('Lecture', error: error, secrets: secrets);
        if (!done.isCompleted) done.completeError(const PlaybackFailed());
      }),
    ];
    try {
      await player.open(media);
      await done.future.timeout(startTimeout);
    } on TimeoutException {
      log('Lecture', error: 'le flux ne démarre pas');
      throw const PlaybackFailed();
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }

  /// Arrête le flux : plus aucun trafic réseau.
  Future<void> stop() {
    _generation++;
    return player.stop();
  }

  Future<void> dispose() => player.dispose();
}

/// Créé à la première lecture, gardé ensuite : un seul lecteur pour l'app.
final playbackProvider = Provider<Playback>((ref) {
  final playback = Playback();
  ref.onDispose(playback.dispose);
  return playback;
});
