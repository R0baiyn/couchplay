import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../accounts/app_settings.dart';
import '../logging.dart';
import '../television.dart';

/// Ce que le lecteur doit ouvrir.
final class PlayRequest {
  const PlayRequest({
    required this.title,
    required this.url,
    required this.userAgent,
    this.secrets = const [],
    this.headers = const {},
    this.audioLanguage,
    this.subtitleLanguage,
    this.start,
  });

  final String title;

  /// Porte les identifiants dans son chemin : jamais loggée sans masquage.
  final Uri url;
  final String userAgent;

  /// En-têtes HTTP en plus du User-Agent (Host quand l'URL porte l'adresse
  /// IP résolue par Cloudflare).
  final Map<String, String> headers;

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
  const PlaybackFailed({this.unreadable = false, this.network = false});

  /// D'après une erreur de mpv : fichier reçu mais illisible (format ou
  /// codec non pris en charge), connexion coupée ou sans réponse, sinon
  /// refus du serveur.
  factory PlaybackFailed.fromMpv(String reason) => PlaybackFailed(
    unreadable: _unreadable.hasMatch(reason),
    network: _network.hasMatch(reason),
  );

  static final _unreadable = RegExp(
    r'codec|decoder|unsupported|unrecognized|recognize file format|'
    r'no video or audio streams',
    caseSensitive: false,
  );

  // Sous Windows, ffmpeg ne nomme pas l'erreur de connexion (« tcp:
  // Connection to tcp://… failed: Error number -138 occurred ») : c'est la
  // forme de la ligne qui compte. Un refus du serveur, lui, ne donne au
  // niveau error que « Failed to open ».
  static final _network = RegExp(
    r'connection to \S+ failed|timed out|timeout|connection refused|'
    r'connection reset|unreachable|broken pipe|resolve',
    caseSensitive: false,
  );

  /// Le serveur a bien envoyé le fichier, mais cet appareil ne sait pas le
  /// lire : réessayer n'y change rien.
  final bool unreadable;

  /// Pas de réponse à temps, ou connexion coupée : le serveur n'a rien
  /// refusé.
  final bool network;

  String get message => unreadable
      ? 'Cette vidéo ne peut pas être lue sur cet appareil : son format '
            'n\'est pas pris en charge.'
      : network
      ? 'La connexion au serveur a échoué (délai dépassé ou réseau coupé). '
            'Vérifie ta connexion, puis réessaie.'
      : 'Le serveur refuse la connexion : un autre appareil utilise '
            'peut-être ton abonnement.';

  @override
  String toString() => message;
}

/// L'ouverture a été remplacée (arrêt, autre ouverture) avant de démarrer :
/// rien à signaler, le flux n'est plus le nôtre.
final class PlaybackAbandoned implements Exception {
  const PlaybackAbandoned();
}

/// Lance [attempt] ; en cas d'échec, réessaie après [delay], au plus
/// [retries] fois. La dernière erreur remonte, et tout de suite une vidéo
/// illisible ou un abandon : réessayer n'y changerait rien.
Future<T> withRetries<T>(
  Future<T> Function() attempt, {
  int retries = 2,
  Duration delay = const Duration(seconds: 1),
  Future<void> Function(Duration) sleep = Future<void>.delayed,
}) async {
  for (var tried = 0; ; tried++) {
    try {
      return await attempt();
    } on Exception catch (e) {
      if (tried >= retries ||
          e is PlaybackAbandoned ||
          (e is PlaybackFailed && e.unreadable)) {
        rethrow;
      }
      await sleep(delay);
    }
  }
}

/// D'où vient ce qu'on regarde.
enum PlaySource { local, stream }

/// Ouvre un contenu par [open] : son fichier téléchargé [file] s'il existe
/// (requête [local], sans rien demander au serveur), sinon le flux
/// ([stream] ; `null` sans compte : rien n'est ouvert, `null` renvoyé).
///
/// - Fichier absent : [dropFile], puis le flux.
/// - Fichier qui ne s'ouvre pas : le flux ; [dropFile] seulement si le flux
///   démarre (le fichier était abîmé). Si le flux échoue aussi (hors ligne,
///   format non pris en charge), le fichier reste.
/// - D-036 : [streaming] passe à `true` avant d'ouvrir un flux, à `false`
///   après une ouverture locale (une lecture locale ne met rien en pause).
///   Un flux refusé par le serveur alors que [downloading] : [pauseDownloads]
///   puis une seule nouvelle ouverture.
Future<PlaySource?> openContent({
  required File? file,
  required PlayRequest Function(File) local,
  required Future<PlayRequest?> Function() stream,
  required Future<void> Function(PlayRequest) open,
  required Future<void> Function() dropFile,
  required void Function(bool) streaming,
  required bool Function() downloading,
  required void Function() pauseDownloads,
}) async {
  var broken = false;
  if (file != null) {
    if (await file.exists()) {
      try {
        await open(local(file));
        streaming(false);
        return PlaySource.local;
      } on PlaybackFailed {
        log('Vidéo téléchargée illisible : lecture par le flux');
        broken = true;
      }
    } else {
      log('Vidéo téléchargée absente : lecture par le flux');
      await dropFile();
    }
  }
  final request = await stream();
  if (request == null) return null;
  streaming(true);
  try {
    await open(request);
  } on PlaybackFailed catch (e) {
    if (e.unreadable || e.network || !downloading()) rethrow;
    log('Flux refusé pendant un téléchargement : téléchargement en pause');
    pauseDownloads();
    await open(request);
  }
  if (broken) await dropFile();
  return PlaySource.stream;
}

/// Propriétés mpv des pistes pour [request], dans l'ordre où les poser :
/// langue audio demandée, sinon le français ; sous-titres de la langue
/// demandée, sinon aucun.
Map<String, String> trackProperties(PlayRequest request) {
  final subtitles = request.subtitleLanguage;
  return {
    'alang': request.audioLanguage ?? 'fr,fre,fra,fr-FR',
    'aid': 'auto',
    'slang': ?subtitles,
    'sid': subtitles == null ? 'no' : 'auto',
  };
}

/// Ligne du journal de mpv qui signale un flux refusé ou coupé (un refus
/// http n'arrive parfois que là).
bool isStreamFailure(String level, String prefix) =>
    level == 'error' &&
    (prefix == 'stream' || prefix == 'ffmpeg' || prefix == 'demux');

/// Rendu vidéo : sur TV avec la lecture directe, MediaCodec affiche
/// directement sur la surface, sans copie ni rendu OpenGL (trop lourds pour
/// les SoC faibles : saccades sur un projecteur, D-065). Réglage éteint par
/// défaut (D-068 : certains décodeurs bloquent après une avance) ; sinon,
/// les défauts de media_kit.
VideoControllerConfiguration videoConfiguration({
  required bool television,
  required bool direct,
}) => television && direct
    ? const VideoControllerConfiguration(
        vo: 'mediacodec_embed',
        hwdec: 'mediacodec',
      )
    : const VideoControllerConfiguration();

/// Seul propriétaire du lecteur de l'app (règle 3) : un seul flux à la fois.
/// Ouvrir un flux remplace le précédent, qui est fermé d'abord.
final class Playback {
  Playback({bool television = false, bool direct = false})
    : player = Player(
        configuration: const PlayerConfiguration(
          title: 'CouchPlay',
          // Explicite : `_start` lit les erreurs du journal de mpv (refus
          // http qui n'arrivent que là).
          logLevel: MPVLogLevel.error,
        ),
      ) {
    if (Platform.isLinux) {
      // Sans interop de décodage matériel : libmpv chargerait VA-API en
      // créant le rendu OpenGL, et `vaInitialize` plante sans pilote VA
      // (WSL, compositeur sans périphérique DRM). La vidéo reste rendue en
      // OpenGL. Posé avant le contrôleur, qui attend la même initialisation
      // (`then` passe avant lui) ; `setProperty` attendrait sinon le
      // contrôleur, déjà attaché.
      final native = player.platform! as NativePlayer;
      unawaited(
        native.waitForPlayerInitialization.then(
          (_) => native.setProperty(
            'gpu-hwdec-interop',
            'no',
            waitForInitialization: false,
          ),
        ),
      );
    }
    controller = VideoController(
      player,
      configuration: videoConfiguration(television: television, direct: direct),
    );
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
  /// Rien ne reste alors en cours de chargement. Lève [PlaybackAbandoned]
  /// si une ouverture plus récente, ou un arrêt, prend la main entre-temps.
  Future<void> open(PlayRequest request) async {
    final generation = ++_generation;
    _abandonStart();
    await player.stop();
    await _tracks(request);
    final media = Media(
      request.url.toString(),
      httpHeaders: {'User-Agent': request.userAgent, ...request.headers},
      start: request.start,
    );
    try {
      await withRetries(() async {
        // Une ouverture plus récente, ou un arrêt, a pris la main.
        if (generation != _generation) throw const PlaybackAbandoned();
        await _start(media, request.secrets);
      });
    } on Exception catch (e) {
      if (generation != _generation) throw const PlaybackAbandoned();
      // mpv peut encore être en train de se connecter : on coupe, pour ne
      // pas garder l'unique connexion derrière le message d'erreur.
      await player.stop();
      throw e is PlaybackFailed ? e : const PlaybackFailed();
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
    for (final MapEntry(:key, :value) in trackProperties(request).entries) {
      await native.setProperty(key, value);
    }
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
      if (!done.isCompleted) {
        done.completeError(PlaybackFailed.fromMpv(reason));
      }
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
        if (opened && isStreamFailure(entry.level, entry.prefix)) {
          fail('${entry.prefix}: ${entry.text}');
        }
      }),
    ];
    try {
      await player.open(media);
      opened = true;
      await started;
    } on TimeoutException {
      log('Lecture', error: 'le flux ne démarre pas');
      throw const PlaybackFailed(network: true);
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
      starting.completeError(const PlaybackAbandoned());
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
/// Le réglage de lecture directe est lu ici, une fois (`read`, pas `watch` :
/// changer de réglage ne recrée jamais le lecteur pendant une lecture).
final playbackProvider = Provider<Playback>((ref) {
  final playback = Playback(
    television: ref.read(televisionProvider),
    direct: ref.read(appSettingsProvider).directVideo,
  );
  ref.onDispose(playback.dispose);
  return playback;
});
