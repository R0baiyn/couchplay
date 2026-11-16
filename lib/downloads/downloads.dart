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

  bool get _onMobileOnly =>
      ref.read(appSettingsProvider).wifiOnly &&
      (ref.read(mobileOnlyNetworkProvider).value ?? false);

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

final class DownloadsNotifier extends Notifier<DownloadsState> {
  DownloadsStore? _store;
  ServerClient? _client;
  String? _accountId;
  late Dio _dio;
  var _disposed = false;

  /// Comptes en cours de suppression ([whileDownloadsReleased]) : rien ne
  /// repart.
  static final _released = <String>{};

  /// Téléchargement en cours de chaque compte, pour [whileDownloadsReleased] :
  /// lu hors du provider, qui dépend du compte actif.
  static final _running = <String, Future<void> Function()>{};

  /// Rangement du dossier fait : rien ne démarre avant.
  Future<void> _tidied = Future.value();

  /// Le téléchargement en cours.
  ({String key, CancelToken cancel, Future<void> done})? _current;

  /// Octets présents dans le fichier partiel en cours.
  var _received = 0;
  final _sinceProgress = Stopwatch();

  @override
  DownloadsState build() {
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
    final store = _store = DownloadsStore(
      File(ref.watch(accountFilesProvider).path(id, 'downloads.json')),
      videos.of(id),
    );
    _client = client;
    _accountId = id;
    // Même chemin réseau que le lecteur : DoH par `HttpOverrides`, en-tête
    // Host et certificat au nom du serveur, User-Agent du compte.
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'User-Agent': userAgent},
      ),
    );
    if (ref.read(downloadAdapterProvider) case final adapter?) {
      _dio.httpClientAdapter = adapter;
    }
    ref.onDispose(() {
      _disposed = true;
      _current?.cancel.cancel();
      _dio.close(force: true);
    });
    ref.listen(downloadHoldsProvider, (_, holds) {
      if (holds.reasons.isEmpty) {
        unawaited(_pump());
      } else {
        _interrupt();
      }
    });
    final entries = store.load();
    _tidied = store.tidy(entries.values);
    Future.microtask(_pump);
    return DownloadsState(entries: entries);
  }

  /// Fichier d'un contenu prêt, ou `null` (pas téléchargé, pas fini) : pour
  /// le lecteur.
  File? fileOf(PlayItem item) {
    final download = state.entries[item.key];
    if (download?.status != DownloadStatus.ready) return null;
    return _store?.fileOf(download!);
  }

  /// Ajoute à la file : un film, un épisode, ou une saison entière. Ce qui
  /// y est déjà est laissé tel quel ; ce qui avait échoué repart.
  Future<void> add(Iterable<PlayItem> items) async {
    if (_store == null) return;
    final entries = {...state.entries};
    for (final item in items) {
      if (!isDownloadable(item)) {
        log('Téléchargement refusé : id ou extension invalide');
        continue;
      }
      final existing = entries[item.key];
      if (existing == null) {
        entries[item.key] = Download(
          item: item,
          addedAt: DateTime.now().toUtc(),
        );
      } else if (existing.status == DownloadStatus.failed) {
        entries[item.key] = existing.copyWith(status: DownloadStatus.queued);
      }
    }
    await _save(entries);
    unawaited(_pump());
  }

  /// Met en pause : la file passe au suivant.
  Future<void> pause(String key) async {
    final download = state.entries[key];
    if (download == null ||
        (download.status != DownloadStatus.queued &&
            download.status != DownloadStatus.running)) {
      return;
    }
    await _stop(key);
    await _set(key, (d) => d.copyWith(status: DownloadStatus.paused));
    unawaited(_pump());
  }

  /// Reprend un téléchargement en pause, ou relance un échec.
  Future<void> resume(String key) async {
    final status = state.entries[key]?.status;
    if (status != DownloadStatus.paused && status != DownloadStatus.failed) {
      return;
    }
    await _set(key, (d) => d.copyWith(status: DownloadStatus.queued));
    unawaited(_pump());
  }

  /// Annule un téléchargement ou supprime un fichier prêt : l'entrée et ses
  /// fichiers disparaissent.
  Future<void> remove(String key) async {
    final download = state.entries[key];
    if (download == null) return;
    await _stop(key);
    if (_disposed) return;
    await _save({...state.entries}..remove(key));
    await _store?.deleteFiles(download);
    unawaited(_pump());
  }

  /// Supprime tout : téléchargements en cours, en attente et fichiers prêts.
  Future<void> removeAll() async {
    final all = state.entries.values.toList();
    final current = _current;
    if (current != null) await _stop(current.key);
    if (_disposed) return;
    await _save(const {});
    for (final download in all) {
      await _store?.deleteFiles(download);
    }
  }

  /// Arrête le téléchargement de [key] s'il est en cours, fichier fermé au
  /// retour.
  Future<void> _stop(String key) async {
    final current = _current;
    if (current == null || current.key != key) return;
    current.cancel.cancel();
    await current.done;
  }

  /// Une pause de toute la file : le téléchargement en cours repasse en
  /// attente, et reprendra à la levée de la pause.
  void _interrupt() {
    final current = _current;
    if (current == null) return;
    unawaited(
      _set(current.key, (d) => d.copyWith(status: DownloadStatus.queued)),
    );
    current.cancel.cancel();
  }

  bool get _blocked =>
      _disposed ||
      _released.contains(_accountId) ||
      ref.read(downloadHoldsProvider).reasons.isNotEmpty;

  /// Lance le premier téléchargement en attente, s'il n'y en a aucun en
  /// cours et que rien ne bloque la file.
  Future<void> _pump() async {
    if (_current != null || _blocked) return;
    await _tidied;
    if (_current != null || _blocked) return;
    final next = state.entries.values
        .where((d) => d.status == DownloadStatus.queued)
        .firstOrNull;
    if (next == null) return;
    final cancel = CancelToken();
    final done = _run(next, cancel);
    _current = (key: next.key, cancel: cancel, done: done);
    final account = _accountId!;
    Future<void> stop() {
      cancel.cancel();
      return done;
    }

    _running[account] = stop;
    await done;
    if (identical(_running[account], stop)) _running.remove(account);
    _current = null;
    if (_disposed) return;
    ref.read(downloadProgressProvider.notifier).publish(null);
    unawaited(_pump());
  }

  Future<void> _run(Download download, CancelToken cancel) async {
    final store = _store!;
    final key = download.key;
    final item = download.item;
    final url = _client!.streamUri(
      item.isEpisode ? ContentKind.series : ContentKind.movies,
      item.id,
      item.extension,
    );
    final part = store.partOf(download);
    final delays = ref.read(downloadRetryDelaysProvider);
    final progress = ref.read(downloadProgressProvider.notifier);
    final space = ref.read(freeSpaceProvider);
    var size = download.size;
    await _set(key, (d) => d.copyWith(status: DownloadStatus.running));
    try {
      // Créé ici, pas avant : un compte sans téléchargement n'a pas de
      // dossier. La suppression du compte arrête ce téléchargement
      // d'abord ([release]) : il ne fait pas revenir le dossier effacé.
      await part.parent.create(recursive: true);
    } on FileSystemException catch (e) {
      log('Dossier des vidéos non créé', error: e.osError?.errorCode);
      return _fail(key, const WriteFailed());
    }
    for (var attempt = 0; ; attempt++) {
      try {
        _received = await part.exists() ? await part.length() : 0;
        size = await transfer(
          dio: _dio,
          url: url,
          part: part,
          cancel: cancel,
          size: size,
          freeSpace: space,
          onProgress: (received, total) {
            _received = received;
            if (total != size) {
              size = total;
              unawaited(_set(key, (d) => d.copyWith(size: total)));
            }
            if (!_sinceProgress.isRunning ||
                _sinceProgress.elapsedMilliseconds >= 250) {
              _sinceProgress
                ..reset()
                ..start();
              if (!_disposed) {
                progress.publish(DownloadProgress(key, received, total));
              }
            }
          },
        );
        await part.rename(store.fileOf(download).path);
        await _set(
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
          // La taille sur le disque : les derniers octets écrits n'ont pas
          // forcément été comptés.
          if (await part.exists()) _received = await part.length();
          await _set(key, (d) => d.copyWith(received: _received));
          return;
        }
        log('Téléchargement', error: e.type);
        await _fail(key, const WriteFailed());
        return;
      } on TransferException catch (e) {
        final retry = e is TransferInterrupted || e is TransferRefused;
        if (retry && ref.read(downloadHoldsProvider).streaming) {
          // D-036 : le serveur refuse sans doute deux flux à la fois ; on
          // attend la sortie du lecteur.
          await _set(
            key,
            (d) =>
                d.copyWith(status: DownloadStatus.queued, received: _received),
          );
          ref
              .read(downloadHoldsProvider.notifier)
              .pauseAll(DownloadHold.playback);
          return;
        }
        if (e is TransferInterrupted && attempt < delays.length) {
          await _set(key, (d) => d.copyWith(received: _received));
          await Future.any([
            Future<void>.delayed(delays[attempt]),
            cancel.whenCancel,
          ]);
          if (cancel.isCancelled) return;
          continue;
        }
        await _fail(key, e);
        return;
      } on FileSystemException catch (e) {
        // Renommage impossible (fichier verrouillé, disque retiré).
        log('Téléchargement non renommé', error: e.osError?.errorCode);
        await _fail(key, const WriteFailed());
        return;
      }
    }
  }

  Future<void> _fail(String key, TransferException error) {
    log('Téléchargement en échec : ${error.message}');
    return _set(
      key,
      (d) => d.copyWith(
        status: DownloadStatus.failed,
        error: error.message,
        received: _received,
      ),
    );
  }

  /// Change l'entrée [key], si elle existe encore.
  Future<void> _set(String key, Download Function(Download) change) {
    final download = state.entries[key];
    if (download == null || _disposed) return Future.value();
    return _save({...state.entries, key: change(download)});
  }

  Future<void> _save(Map<String, Download> entries) {
    if (_disposed) return Future.value();
    state = DownloadsState(entries: entries);
    return _store?.save(entries) ?? Future.value();
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
