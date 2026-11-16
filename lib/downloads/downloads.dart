import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/account_files.dart';
import '../accounts/account_store.dart';
import '../accounts/server_session.dart';
import '../library/library.dart';
import '../library/library_store.dart';
import '../logging.dart';
import '../server/models.dart';
import '../server/server_client.dart';
import '../settings/app_settings.dart';
import 'download.dart';
import 'free_space.dart';
import 'transfer.dart';

/// Pourquoi toute la file attend.
enum DownloadHold {
  /// Android, app quittée (D-035) : reprend au retour.
  background,

  /// Le lecteur l'a demandé (le serveur refusait la lecture en flux), ou un
  /// téléchargement refusé ou coupé pendant une lecture attend la sortie du
  /// lecteur (D-036).
  playback,

  /// Réseau mobile avec « Télécharger en Wi-Fi seulement » (D-037).
  mobileNetwork,
}

/// Les pauses de toute la file, et si une lecture en flux est ouverte.
final class DownloadHolds {
  const DownloadHolds({this.reasons = const {}, this.streaming = false});

  final Set<DownloadHold> reasons;

  /// Une lecture en flux est ouverte : le téléchargement continue, mais un
  /// refus ou une coupure le fait attendre la sortie du lecteur au lieu
  /// d'échouer.
  final bool streaming;

  bool get waitingForWifi => reasons.contains(DownloadHold.mobileNetwork);
}

/// Pauses de toute la file. API du lecteur (S024) :
/// - `streaming = true` à l'ouverture d'une lecture en flux, `false` à la
///   sortie du lecteur (lève aussi [DownloadHold.playback]) ;
/// - `pauseAll(DownloadHold.playback)` si le serveur refuse la lecture
///   pendant un téléchargement, avant de la relancer.
final downloadHoldsProvider =
    NotifierProvider<DownloadHoldsNotifier, DownloadHolds>(
      DownloadHoldsNotifier.new,
    );

final class DownloadHoldsNotifier extends Notifier<DownloadHolds> {
  @override
  DownloadHolds build() {
    if (ref.read(pauseInBackgroundProvider)) {
      final lifecycle = AppLifecycleListener(
        onHide: () => pauseAll(DownloadHold.background),
        onShow: () => resumeAll(DownloadHold.background),
      );
      ref.onDispose(lifecycle.dispose);
    }
    ref.listen(appSettingsProvider.select((s) => s.wifiOnly), (_, _) {
      _network();
    });
    ref.listen(mobileOnlyNetworkProvider, (_, _) => _network());
    return DownloadHolds(
      reasons: {if (_onMobileOnly) DownloadHold.mobileNetwork},
    );
  }

  /// Tant que le type de réseau n'est pas connu, la file attend : un
  /// téléchargement repris au démarrage ne part pas sur le forfait mobile.
  bool get _onMobileOnly =>
      ref.read(appSettingsProvider).wifiOnly &&
      switch (ref.read(mobileOnlyNetworkProvider)) {
        AsyncData(:final value) => value,
        AsyncError() => false,
        _ => true,
      };

  void _network() => _onMobileOnly
      ? pauseAll(DownloadHold.mobileNetwork)
      : resumeAll(DownloadHold.mobileNetwork);

  void pauseAll(DownloadHold reason) {
    if (state.reasons.contains(reason)) return;
    state = DownloadHolds(
      reasons: {...state.reasons, reason},
      streaming: state.streaming,
    );
  }

  void resumeAll(DownloadHold reason) {
    if (!state.reasons.contains(reason)) return;
    state = DownloadHolds(
      reasons: {...state.reasons}..remove(reason),
      streaming: state.streaming,
    );
  }

  /// Voir [DownloadHolds.streaming]. La sortie du lecteur lève
  /// [DownloadHold.playback].
  set streaming(bool open) {
    state = DownloadHolds(
      reasons: open
          ? state.reasons
          : ({...state.reasons}..remove(DownloadHold.playback)),
      streaming: open,
    );
  }
}

/// Android seulement : l'app quittée met la file en pause (D-035). Sous
/// Windows et Linux, une fenêtre réduite continue.
final pauseInBackgroundProvider = Provider<bool>((ref) => Platform.isAndroid);

/// `true` sur un réseau mobile sans Wi-Fi ni Ethernet. Toujours `false`
/// hors Android, et quand le système ne répond pas : le réseau est alors
/// accepté.
final mobileOnlyNetworkProvider = StreamProvider<bool>((ref) async* {
  if (!Platform.isAndroid) {
    yield false;
    return;
  }
  final connectivity = Connectivity();
  try {
    yield isMobileOnly(await connectivity.checkConnectivity());
    yield* connectivity.onConnectivityChanged.map(isMobileOnly);
  } on Object catch (e) {
    log('État du réseau illisible', error: e.runtimeType);
    yield false;
  }
});

bool isMobileOnly(List<ConnectivityResult> results) =>
    results.contains(ConnectivityResult.mobile) &&
    !results.contains(ConnectivityResult.wifi) &&
    !results.contains(ConnectivityResult.ethernet);

/// Place libre d'un dossier ([freeSpace]), remplacée dans les tests.
final freeSpaceProvider = Provider<Future<int?> Function(Directory)>(
  (ref) => freeSpace,
);

/// Attentes avant chaque nouvelle tentative après une coupure ; ensuite,
/// échec.
final downloadRetryDelaysProvider = Provider<List<Duration>>(
  (ref) => const [
    Duration(seconds: 2),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ],
);

/// Remplace le réseau dans les tests.
final downloadAdapterProvider = Provider<HttpClientAdapter?>((ref) => null);

/// Avancement du téléchargement en cours, publié à part (quelques fois par
/// seconde au plus) : seul ce qui l'affiche se reconstruit.
final class DownloadProgress {
  const DownloadProgress(this.key, this.received, this.size);

  final String key;
  final int received;

  /// 0 si inconnue.
  final int size;

  double? get fraction =>
      size > 0 ? (received / size).clamp(0, 1).toDouble() : null;
}

final downloadProgressProvider =
    NotifierProvider<DownloadProgressNotifier, DownloadProgress?>(
      DownloadProgressNotifier.new,
    );

final class DownloadProgressNotifier extends Notifier<DownloadProgress?> {
  @override
  DownloadProgress? build() => null;

  void publish(DownloadProgress? progress) => state = progress;
}

/// Téléchargements du compte actif, dans l'ordre d'ajout.
final class DownloadsState {
  const DownloadsState({this.entries = const {}});

  /// Par clé `movie:<id>` ou `episode:<id>`.
  final Map<String, Download> entries;
}

/// File des téléchargements du compte actif : un seul à la fois, dans
/// l'ordre d'ajout. Rechargée au changement de compte : la file du compte
/// quitté s'arrête (son fichier partiel reste pour une reprise).
///
/// `main()` l'écoute dès le démarrage : un téléchargement interrompu
/// reprend sans attendre l'écran des téléchargements.
final downloadsProvider = NotifierProvider<DownloadsNotifier, DownloadsState>(
  DownloadsNotifier.new,
);

/// Ce qui vaut pour une construction du provider (un compte, un client) :
/// Riverpod peut garder la même instance du notifier d'une construction à
/// l'autre, et un transfert de la précédente ne doit rien toucher ensuite.
final class _Session {
  _Session(this.store, this.client, this.accountId, this.dio);

  final DownloadsStore store;
  final ServerClient client;
  final String accountId;
  final Dio dio;
  var disposed = false;

  /// Rangement du dossier fait : rien ne démarre avant.
  Future<void> tidied = Future.value();

  /// Le téléchargement en cours.
  ({String key, CancelToken cancel, Future<void> done})? current;

  /// Octets présents dans le fichier partiel en cours.
  var received = 0;
  final sinceProgress = Stopwatch();

  /// Affiches en cours de téléchargement, par nom de fichier.
  final posters = <String>{};
  final posterCancel = CancelToken();

  /// Fin de la dernière affiche demandée : une seule requête à la fois
  /// (au lancement, toutes les affiches manquantes sont redemandées).
  Future<void> posterQueue = Future.value();
}

class DownloadsNotifier extends Notifier<DownloadsState> {
  _Session? _session;

  /// Comptes en cours de suppression ([whileDownloadsReleased]) : rien ne
  /// repart.
  static final _released = <String>{};

  /// Téléchargement en cours de chaque compte, pour [whileDownloadsReleased]
  /// et pour la construction suivante du même compte : lu hors du provider,
  /// qui dépend du compte actif.
  static final _running = <String, Future<void> Function()>{};

  @override
  DownloadsState build() {
    _session = null;
    final account = ref.watch(
      activeAccountProvider.select(
        (a) => a == null ? null : (a.id, a.userAgent),
      ),
    );
    final client = ref.watch(serverClientProvider);
    final videos = ref.watch(downloadFilesProvider);
    if (account == null || client == null || videos == null) {
      return const DownloadsState();
    }
    final (id, userAgent) = account;
    final store = DownloadsStore(
      File(ref.watch(accountFilesProvider).path(id, 'downloads.json')),
      videos.of(id),
    );
    // Même chemin réseau que le lecteur : DoH par `HttpOverrides`, en-tête
    // Host et certificat au nom du serveur, User-Agent du compte.
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'User-Agent': userAgent},
      ),
    );
    if (ref.read(downloadAdapterProvider) case final adapter?) {
      dio.httpClientAdapter = adapter;
    }
    final session = _session = _Session(store, client, id, dio);
    ref.onDispose(() {
      session.disposed = true;
      session.current?.cancel.cancel();
      session.posterCancel.cancel();
      dio.close(force: true);
    });
    _watched.clear();
    ref.listen(libraryProvider, (previous, library) {
      _onLibrary(id, previous, library);
    });
    ref.listen(downloadHoldsProvider, (_, holds) {
      if (holds.reasons.isEmpty) {
        unawaited(_pump(session));
      } else {
        _interrupt(session);
      }
    });
    final entries = store.load();
    session.tidied = store.tidy(entries.values);
    Future.microtask(() {
      unawaited(_pump(session));
      // Rattrapage : une affiche manquée (réseau coupé, app fermée trop
      // tôt) est redemandée à chaque lancement.
      for (final download in entries.values) {
        unawaited(_fetchPoster(session, download));
      }
    });
    return DownloadsState(entries: entries);
  }

  /// Un téléchargement tourne : pour le lecteur, qui le met en pause si le
  /// serveur refuse la lecture (D-036).
  bool get downloading =>
      state.entries.values.any((d) => d.status == DownloadStatus.running);

  /// Lecteurs ouverts (deux un instant, pendant la fermeture du premier).
  var _players = 0;

  /// Vidéos prêtes passées à « vu » avec « Effacer une fois vu » : effacées
  /// une fois le lecteur fermé, jamais pendant (fichier ouvert).
  final _watched = <String>{};

  void playerOpened() => _players++;

  /// À appeler une fois le lecteur arrêté (fichier fermé).
  void playerClosed() {
    _players--;
    _deleteWatched();
  }

  /// D-037 : un contenu prêt qui passe à « vu » (fin de lecture ou « Marquer
  /// comme vu ») perd sa vidéo. Un contenu déjà vu puis téléchargé la garde.
  void _onLibrary(String accountId, Library? previous, Library library) {
    // Bibliothèque d'un autre compte : changement de compte en cours.
    if (previous == null || ref.read(activeAccountProvider)?.id != accountId) {
      return;
    }
    if (!ref.read(appSettingsProvider).deleteWatched) return;
    for (final MapEntry(:key, value: progress) in library.progress.entries) {
      if (progress.watched &&
          !(previous.progress[key]?.watched ?? false) &&
          state.entries[key]?.status == DownloadStatus.ready) {
        _watched.add(key);
      }
    }
    _deleteWatched();
  }

  void _deleteWatched() {
    final session = _session;
    if (_players > 0 || session == null || session.disposed) return;
    final keys = [..._watched];
    _watched.clear();
    for (final key in keys) {
      log('Vidéo vue effacée');
      unawaited(remove(key));
    }
  }

  /// Dossier des vidéos du compte actif, `null` sans compte : pour l'ouvrir
  /// dans l'explorateur de fichiers (PC).
  Directory? get folder => _session?.store.videos;

  /// Fichier d'un contenu prêt, ou `null` (pas téléchargé, pas fini) : pour
  /// le lecteur.
  File? fileOf(PlayItem item) {
    final download = state.entries[item.key];
    if (download == null || download.status != DownloadStatus.ready) {
      return null;
    }
    return _session?.store.fileOf(download);
  }

  /// Affiche enregistrée de [item] (celle de sa série pour un épisode), ou
  /// `null` si elle n'est pas (encore) sur le disque : pour la page des
  /// téléchargements, qui s'affiche hors ligne.
  File? posterOf(PlayItem item) {
    final download = state.entries[item.key];
    final poster = download == null ? null : _session?.store.posterOf(download);
    return poster != null && poster.existsSync() ? poster : null;
  }

  /// Ajoute à la file : un film, un épisode, ou une saison entière. Ce qui
  /// y est déjà est laissé tel quel ; ce qui avait échoué repart.
  Future<void> add(Iterable<PlayItem> items) async {
    final session = _session;
    if (session == null) return;
    final entries = {...state.entries};
    final added = <Download>[];
    for (final item in items) {
      if (!isDownloadable(item)) {
        log('Téléchargement refusé : id ou extension invalide');
        continue;
      }
      final existing = entries[item.key];
      if (existing == null) {
        added.add(
          entries[item.key] = Download(
            item: item,
            addedAt: DateTime.now().toUtc(),
          ),
        );
      } else if (existing.status == DownloadStatus.failed) {
        entries[item.key] = existing.copyWith(status: DownloadStatus.queued);
      }
    }
    await _save(session, entries);
    unawaited(_pump(session));
    for (final download in added) {
      unawaited(_fetchPoster(session, download));
    }
  }

  /// Enregistre l'affiche de [download] à côté des vidéos, une fois par
  /// nom (une saison entière : une affiche). Par le client du transfert ;
  /// un échec laisse la page retomber sur le réseau puis sur l'icône.
  Future<void> _fetchPoster(_Session session, Download download) async {
    final poster = download.item.poster;
    final url = poster == null ? null : Uri.tryParse(poster);
    final name = download.posterName;
    if (url == null || !session.posters.add(name)) return;
    final previous = session.posterQueue;
    final done = Completer<void>();
    session.posterQueue = done.future;
    try {
      await previous;
      if (session.disposed) return;
      await session.tidied;
      final store = session.store;
      if (await store.posterOf(download).exists()) return;
      final bytes = await fetchPoster(session.dio, url, session.posterCancel);
      if (bytes == null) {
        log('Affiche non téléchargée');
        return;
      }
      // Relu juste avant d'écrire : compte supprimé (dossier effacé),
      // vidéo déjà retirée.
      if (!_claimed(session, name)) return;
      await store.writePoster(download, bytes);
      // Compte quitté pendant l'écriture : l'affiche reste, le manifeste
      // la réclame peut-être encore (sinon le rangement l'effacera).
      if (session.disposed) return;
      // Retirée pendant l'écriture : l'affiche part avec elle.
      if (!_claimed(session, name)) {
        await store.deletePoster(download);
        return;
      }
      // Nouvelle liste : la page relit les affiches.
      state = DownloadsState(entries: {...state.entries});
    } on FileSystemException catch (e) {
      log('Affiche non écrite', error: e.osError?.errorCode);
    } finally {
      session.posters.remove(name);
      done.complete();
    }
  }

  /// Une entrée du compte encore actif réclame l'affiche [name].
  bool _claimed(_Session session, String name) =>
      !session.disposed &&
      !_released.contains(session.accountId) &&
      state.entries.values.any((d) => d.posterName == name);

  /// Met en pause : la file passe au suivant.
  Future<void> pause(String key) async {
    final session = _session;
    final status = state.entries[key]?.status;
    if (session == null ||
        (status != DownloadStatus.queued && status != DownloadStatus.running)) {
      return;
    }
    await _stop(session, key);
    await _set(session, key, (d) => d.copyWith(status: DownloadStatus.paused));
    unawaited(_pump(session));
  }

  /// Reprend un téléchargement en pause, ou relance un échec.
  Future<void> resume(String key) async {
    final session = _session;
    final status = state.entries[key]?.status;
    if (session == null ||
        (status != DownloadStatus.paused && status != DownloadStatus.failed)) {
      return;
    }
    await _set(session, key, (d) => d.copyWith(status: DownloadStatus.queued));
    unawaited(_pump(session));
  }

  /// Annule un téléchargement ou supprime un fichier prêt : l'entrée et ses
  /// fichiers disparaissent.
  Future<void> remove(String key) async {
    final session = _session;
    final download = state.entries[key];
    if (session == null || download == null) return;
    await _stop(session, key);
    if (session.disposed) return;
    await _save(session, {...state.entries}..remove(key));
    await session.store.deleteFiles(download);
    // L'affiche d'une série part avec son dernier épisode.
    if (!session.disposed &&
        !state.entries.values.any((d) => d.posterName == download.posterName)) {
      await session.store.deletePoster(download);
    }
    unawaited(_pump(session));
  }

  /// Supprime tout : téléchargements en cours, en attente et fichiers prêts.
  Future<void> removeAll() async {
    final session = _session;
    if (session == null) return;
    final all = state.entries.values.toList();
    // Vidée d'abord : rien ne repart pendant l'arrêt du transfert en cours.
    await _save(session, const {});
    if (session.current case final current?) {
      await _stop(session, current.key);
    }
    for (final download in all) {
      await session.store.deleteFiles(download);
      await session.store.deletePoster(download);
    }
  }

  /// Arrête le téléchargement de [key] s'il est en cours, fichier fermé au
  /// retour.
  Future<void> _stop(_Session session, String key) async {
    final current = session.current;
    if (current == null || current.key != key) return;
    current.cancel.cancel();
    await current.done;
  }

  /// Une pause de toute la file : le téléchargement en cours repasse en
  /// attente, et reprendra à la levée de la pause.
  void _interrupt(_Session session) {
    final current = session.current;
    if (current == null) return;
    // Seulement s'il tourne encore : un téléchargement qui vient de finir
    // (prêt, la file pas encore passée au suivant) serait repris de zéro.
    unawaited(
      _set(
        session,
        current.key,
        (d) => d.status == DownloadStatus.running
            ? d.copyWith(status: DownloadStatus.queued)
            : d,
      ),
    );
    current.cancel.cancel();
  }

  bool _blocked(_Session session) =>
      session.disposed ||
      _released.contains(session.accountId) ||
      ref.read(downloadHoldsProvider).reasons.isNotEmpty;

  /// Lance le premier téléchargement en attente, s'il n'y en a aucun en
  /// cours et que rien ne bloque la file.
  Future<void> _pump(_Session session) async {
    if (session.current != null || _blocked(session)) return;
    await session.tidied;
    if (session.current != null || _blocked(session)) return;
    final account = session.accountId;
    // Le même compte rechargé (User-Agent modifié) : le transfert de la
    // construction précédente ferme d'abord son fichier partiel.
    if (_running[account] case final previous?) {
      await previous();
      if (session.current != null || _blocked(session)) return;
    }
    final next = state.entries.values
        .where((d) => d.status == DownloadStatus.queued)
        .firstOrNull;
    if (next == null) return;
    final cancel = CancelToken();
    final done = _run(session, next, cancel);
    session.current = (key: next.key, cancel: cancel, done: done);
    Future<void> stop() {
      cancel.cancel();
      return done;
    }

    _running[account] = stop;
    await done;
    if (identical(_running[account], stop)) _running.remove(account);
    session.current = null;
    if (session.disposed) return;
    ref.read(downloadProgressProvider.notifier).publish(null);
    unawaited(_pump(session));
  }

  Future<void> _run(
    _Session session,
    Download download,
    CancelToken cancel,
  ) async {
    final store = session.store;
    final key = download.key;
    final item = download.item;
    final url = session.client.streamUri(
      item.isEpisode ? ContentKind.series : ContentKind.movies,
      item.id,
      item.extension,
    );
    final part = store.partOf(download);
    final delays = ref.read(downloadRetryDelaysProvider);
    final progress = ref.read(downloadProgressProvider.notifier);
    final holds = ref.read(downloadHoldsProvider.notifier);
    final space = ref.read(freeSpaceProvider);
    var size = download.size;
    await _set(session, key, (d) => d.copyWith(status: DownloadStatus.running));
    try {
      // Créé ici, pas avant : un compte sans téléchargement n'a pas de
      // dossier. La suppression du compte arrête ce téléchargement
      // d'abord ([whileDownloadsReleased]) : il ne fait pas revenir le
      // dossier effacé.
      await part.parent.create(recursive: true);
    } on FileSystemException catch (e) {
      log('Dossier des vidéos non créé', error: e.osError?.errorCode);
      return _fail(session, key, const WriteFailed());
    }
    for (var attempt = 0; ; attempt++) {
      try {
        session.received = await part.exists() ? await part.length() : 0;
        size = await transfer(
          dio: session.dio,
          url: url,
          part: part,
          cancel: cancel,
          size: size,
          freeSpace: space,
          onProgress: (received, total) {
            session.received = received;
            if (total != size) {
              size = total;
              unawaited(_set(session, key, (d) => d.copyWith(size: total)));
            }
            final clock = session.sinceProgress;
            if (!clock.isRunning || clock.elapsedMilliseconds >= 250) {
              clock
                ..reset()
                ..start();
              if (!session.disposed) {
                progress.publish(DownloadProgress(key, received, total));
              }
            }
          },
        );
        await part.rename(store.fileOf(download).path);
        await _set(
          session,
          key,
          (d) => d.copyWith(
            status: DownloadStatus.ready,
            size: size,
            received: size,
          ),
        );
        return;
      } on DioException catch (e) {
        // Arrêté par une pause, une annulation ou le changement de compte :
        // l'état est réglé par celui qui l'a demandé.
        if (CancelToken.isCancel(e)) {
          // La taille sur le disque : les derniers octets reçus n'ont pas
          // forcément été écrits.
          if (await part.exists()) session.received = await part.length();
          await _set(
            session,
            key,
            (d) => d.copyWith(received: session.received),
          );
          return;
        }
        log('Téléchargement', error: e.type);
        return _fail(session, key, const WriteFailed());
      } on TransferException catch (e) {
        final retry = e is TransferInterrupted || e is TransferRefused;
        if (retry &&
            !session.disposed &&
            ref.read(downloadHoldsProvider).streaming) {
          // D-036 : le serveur refuse sans doute deux flux à la fois ; on
          // attend la sortie du lecteur.
          await _set(
            session,
            key,
            (d) => d.copyWith(
              status: DownloadStatus.queued,
              received: session.received,
            ),
          );
          // Relu après l'écriture : le lecteur a pu se fermer entre-temps,
          // et rien ne lèverait plus la pause.
          if (!session.disposed && ref.read(downloadHoldsProvider).streaming) {
            holds.pauseAll(DownloadHold.playback);
          }
          return;
        }
        if (e is TransferInterrupted && attempt < delays.length) {
          await _set(
            session,
            key,
            (d) => d.copyWith(received: session.received),
          );
          await Future.any([
            Future<void>.delayed(delays[attempt]),
            cancel.whenCancel,
          ]);
          if (cancel.isCancelled) return;
          continue;
        }
        return _fail(session, key, e);
      } on FileSystemException catch (e) {
        // Renommage impossible (fichier verrouillé, disque retiré).
        log('Téléchargement non renommé', error: e.osError?.errorCode);
        return _fail(session, key, const WriteFailed());
      }
    }
  }

  Future<void> _fail(_Session session, String key, TransferException error) {
    log('Téléchargement en échec : ${error.message}');
    return _set(
      session,
      key,
      (d) => d.copyWith(
        status: DownloadStatus.failed,
        error: error.message,
        received: session.received,
      ),
    );
  }

  /// Change l'entrée [key], si elle existe encore.
  Future<void> _set(
    _Session session,
    String key,
    Download Function(Download) change,
  ) {
    // Avant de lire `state` : illisible une fois le provider détruit.
    if (session.disposed) return Future.value();
    final download = state.entries[key];
    if (download == null) return Future.value();
    return _save(session, {...state.entries, key: change(download)});
  }

  Future<void> _save(_Session session, Map<String, Download> entries) {
    if (session.disposed) return Future.value();
    state = DownloadsState(entries: entries);
    return session.store.save(entries);
  }
}

/// Suppression du compte [accountId] : arrête d'abord son téléchargement en
/// cours et attend que son fichier soit fermé, puis lance [delete] (Windows
/// n'efface pas un fichier ouvert). Rien ne repart pour ce compte pendant
/// ce temps.
Future<void> whileDownloadsReleased(
  String accountId,
  Future<void> Function() delete,
) async {
  DownloadsNotifier._released.add(accountId);
  try {
    await DownloadsNotifier._running[accountId]?.call();
    await delete();
  } finally {
    DownloadsNotifier._released.remove(accountId);
  }
}
