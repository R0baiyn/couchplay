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
    this.audioLanguage,
    this.subtitleLanguage,
    this.start,
  });

  final String title;

  /// Porte les identifiants dans son chemin : jamais loggée sans masquage.
  final Uri url;
  final String userAgent;

  /// Identifiants du compte, masqués dans tout message du lecteur.
  final List<String> secrets;

  /// Langues des pistes à choisir si elles existent (code du fichier, `fre`
  /// par exemple) : celles de l'épisode précédent. Sinon, audio français et
  /// pas de sous-titres.
  final String? audioLanguage;
  final String? subtitleLanguage;

  /// Position de départ, appliquée par mpv dès le chargement du fichier.
  final Duration? start;
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

  /// Délai maximal pour que le flux démarre (en-têtes reçus, lecture
  /// commencée). Trois essais au pire : moins d'une minute avant le message.
  static const startTimeout = Duration(seconds: 15);

  var _generation = 0;
  Completer<void>? _starting;

  /// Ticket de l'ouverture en cours, à lire juste après l'appel à [open] :
  /// [stop] avec un ticket périmé ne fait rien. Ainsi l'arrêt tardif d'un
  /// écran qu'on quitte (fin de son animation) ne coupe pas le film suivant,
  /// déjà lancé.
  int get ticket => _generation;

  /// Ouvre [request] ; lève [PlaybackFailed] si le flux ne démarre pas
  /// après les nouvelles tentatives (refus du serveur, réseau coupé…).
  /// Rien ne reste alors en cours de chargement.
  Future<void> open(PlayRequest request) async {
    final generation = ++_generation;
    _abandonStart();
    await player.stop();
    await _tracks(request);
    final media = Media(
      request.url.toString(),
      httpHeaders: {'User-Agent': request.userAgent},
      start: request.start,
    );
    try {
      await withRetries(() async {
        // Une ouverture plus récente, ou un arrêt, a pris la main.
        if (generation != _generation) return;
        await _start(media, request.secrets);
      });
    } on Exception {
      if (generation != _generation) return;
      // mpv peut encore être en train de se connecter : on coupe, pour ne
      // pas garder l'unique connexion derrière le message d'erreur.
      await player.stop();
      throw const PlaybackFailed();
    }
  }

  /// Par défaut, piste audio française si elle existe et sous-titres
  /// désactivés : les fichiers marquent souvent une piste anglaise « par
  /// défaut ». Remis à chaque ouverture, sinon le choix fait sur un film
  /// suivrait au suivant. mpv retombe sur sa piste par défaut si la langue
  /// demandée manque.
  Future<void> _tracks(PlayRequest request) async {
    final native = player.platform;
    if (native is! NativePlayer) return;
    await native.setProperty(
      'alang',
      request.audioLanguage ?? 'fr,fre,fra,fr-FR',
    );
    await native.setProperty('aid', 'auto');
    final subtitles = request.subtitleLanguage;
    if (subtitles != null) await native.setProperty('slang', subtitles);
    await native.setProperty('sid', subtitles == null ? 'no' : 'auto');
  }

  Future<void> _start(Media media, List<String> secrets) async {
    final done = _starting = Completer<void>();
    // Écouté dès maintenant : une erreur arrivée pendant `open` ne doit pas
    // rester une erreur non écoutée.
    final started = done.future.timeout(startTimeout);
    // Un abandon (arrêt, autre ouverture) peut survenir avant le `await` :
    // cette écoute évite qu'il soit signalé comme erreur non traitée.
    unawaited(started.then<void>((_) {}, onError: (_) {}));
    var opened = false;
    void fail(String reason) {
      log('Lecture', error: reason, secrets: secrets);
      if (!done.isCompleted) done.completeError(const PlaybackFailed());
    }

    final subscriptions = [
      // Démarré : durée connue, ou position qui avance (fichier sans durée).
      player.stream.duration.listen((d) {
        if (opened && d > Duration.zero && !done.isCompleted) done.complete();
      }),
      player.stream.position.listen((p) {
        if (opened && p > Duration.zero && !done.isCompleted) done.complete();
      }),
      // Les erreurs d'avant `open` viennent du média précédent : ignorées.
      // Le message de mpv recopie souvent l'URL : loggé masqué.
      player.stream.error.listen((error) {
        if (opened) fail(error);
      }),
      // Un refus http (403, 404…) n'arrive parfois que dans le journal.
      player.stream.log.listen((entry) {
        final failure =
            entry.level == 'error' &&
            (entry.prefix == 'stream' ||
                entry.prefix == 'ffmpeg' ||
                entry.prefix == 'demux');
        if (opened && failure) fail('${entry.prefix}: ${entry.text}');
      }),
    ];
    try {
      await player.open(media);
      opened = true;
      await started;
    } on TimeoutException {
      log('Lecture', error: 'le flux ne démarre pas');
      throw const PlaybackFailed();
    } finally {
      if (identical(_starting, done)) _starting = null;
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }

  /// Un démarrage en attente n'attend pas son délai complet s'il est
  /// remplacé : il se termine aussitôt.
  void _abandonStart() {
    final starting = _starting;
    if (starting != null && !starting.isCompleted) {
      starting.completeError(const PlaybackFailed());
    }
    _starting = null;
  }

  /// Arrête le flux : plus aucun trafic réseau. Avec [ticket] (voir
  /// [ticket]), ne fait rien si une autre ouverture a eu lieu depuis.
  Future<void> stop([int? ticket]) {
    if (ticket != null && ticket != _generation) return Future.value();
    _generation++;
    _abandonStart();
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
