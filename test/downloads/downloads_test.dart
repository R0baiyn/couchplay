import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/downloads/download.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/library/library.dart';
import 'package:couchplay/library/library_store.dart';
import 'package:couchplay/player/playback.dart';
import 'package:couchplay/settings/app_settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'video_server.dart';

PlayItem _movie(String id) =>
    PlayItem.movie(id: id, extension: 'mkv', name: 'Film $id');

Account _account(String id) => Account(
  id: id,
  name: id,
  host: 'http://example.com',
  username: 'moi',
  password: 'p$id',
  userAgent: defaultUserAgent,
);

final _source = Uint8List.fromList(List.generate(1000, (i) => i % 251));

/// Un conteneur avec les comptes `a` (actif) et `b`, des dossiers
/// temporaires et le serveur simulé [server].
final class _Harness {
  _Harness._(this.container, this.server, this.root, this.accounts);

  final ProviderContainer container;
  final VideoServer server;
  final Directory root;
  final AccountStore accounts;

  static Future<_Harness> start({
    VideoServer? server,
    Override? freeSpace,
    bool background = false,
    bool mobileOnly = false,
    Stream<bool> Function()? network,
    void Function(Directory root)? before,
  }) async {
    final root = Directory.systemTemp.createTempSync('couchplay_queue_');
    addTearDown(() async {
      // Écritures du manifeste encore en file : on les laisse finir.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // Sans effet sur les tests suivants.
      }
    });
    FlutterSecureStorage.setMockInitialValues({});
    final accounts = await AccountStore.open();
    await accounts.save(
      const AccountsState()
          .withAccount(_account('a'))
          .withAccount(_account('b')),
    );
    final files = AccountFiles(Directory('${root.path}/accounts'));
    await files.sync({'a', 'b'});
    before?.call(root);
    final video = server ?? VideoServer(_source);
    final container = ProviderContainer.test(
      overrides: [
        accountStoreProvider.overrideWithValue(accounts),
        accountFilesProvider.overrideWithValue(files),
        downloadFilesProvider.overrideWithValue(
          AccountFiles(Directory('${root.path}/downloads')),
        ),
        downloadAdapterProvider.overrideWithValue(video),
        downloadRetryDelaysProvider.overrideWithValue(const [
          Duration.zero,
          Duration.zero,
        ]),
        if (freeSpace == null)
          freeSpaceProvider.overrideWithValue((_) async => null),
        pauseInBackgroundProvider.overrideWithValue(background),
        mobileOnlyNetworkProvider.overrideWith(
          (ref) => network?.call() ?? Stream.value(mobileOnly),
        ),
        ?freeSpace,
      ],
    );
    container.listen(downloadsProvider, (_, _) {});
    return _Harness._(container, video, root, accounts);
  }

  DownloadsNotifier get notifier => container.read(downloadsProvider.notifier);
  Map<String, Download> get entries =>
      container.read(downloadsProvider).entries;
  DownloadStatus? status(String id) => entries['movie:$id']?.status;

  File video(String account, String name) =>
      File('${root.path}/downloads/$account/$name');

  /// Attend que [condition] soit vraie (5 s au plus).
  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 500 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue, reason: 'condition jamais atteinte');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'un à la fois, dans l\'ordre d\'ajout, jusqu\'au fichier prêt',
    () async {
      final h = await _Harness.start();

      await h.notifier.add([_movie('1'), _movie('2')]);
      expect(h.status('2'), DownloadStatus.queued);
      await h.until(() => h.status('2') == DownloadStatus.ready);

      expect(h.status('1'), DownloadStatus.ready);
      expect(h.video('a', 'movie-1.mkv').readAsBytesSync(), _source);
      expect(h.video('a', 'movie-1.mkv.part').existsSync(), isFalse);
      expect(h.notifier.fileOf(_movie('1'))!.path, endsWith('movie-1.mkv'));
      expect(h.notifier.fileOf(_movie('3')), isNull);
      expect(h.entries['movie:1']!.size, 1000);
      expect(h.server.ranges, [null, null]);
      // Ni l'hôte ni les identifiants du compte dans le manifeste écrit.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final manifest = File('${h.root.path}/accounts/a/downloads.json')
          .readAsStringSync();
      expect(manifest, contains('movie:2'));
      for (final secret in ['"moi"', 'mdpa', 'example.com', 'http']) {
        expect(manifest, isNot(contains(secret)), reason: secret);
      }
    },
  );

  test('tout supprimer pendant un téléchargement : rien ne repart', () async {
    final server = VideoServer(_source, cutAt: 500, hangAtCut: true);
    final h = await _Harness.start(server: server);
    await h.notifier.add([_movie('1'), _movie('2')]);
    await server.reachedCut;

    await h.notifier.removeAll();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(h.entries, isEmpty);
    expect(server.ranges, hasLength(1));
    expect(Directory('${h.root.path}/downloads/a').listSync(), isEmpty);
  });

  test('compte modifié pendant un téléchargement : fichier intact', () async {
    final server = VideoServer(_source, cutAt: 500, hangAtCut: true);
    final h = await _Harness.start(server: server);
    await h.notifier.add([_movie('1')]);
    await server.reachedCut;

    server.cutAt = null;
    final edited = _account('a');
    await h.container
        .read(accountsProvider.notifier)
        .save(
          Account(
            id: edited.id,
            name: edited.name,
            host: edited.host,
            username: edited.username,
            password: edited.password,
            userAgent: 'Autre/1.0',
          ),
        );
    await h.until(() => h.status('1') == DownloadStatus.ready);

    expect(h.video('a', 'movie-1.mkv').readAsBytesSync(), _source);
    expect(server.ranges.last, startsWith('bytes='));
  });

  test('ajouter ce qui y est déjà ne change rien', () async {
    final h = await _Harness.start();
    await h.notifier.add([_movie('1')]);
    await h.until(() => h.status('1') == DownloadStatus.ready);

    await h.notifier.add([_movie('1')]);

    expect(h.status('1'), DownloadStatus.ready);
    expect(h.server.ranges, hasLength(1));
  });

  test('au démarrage, un téléchargement interrompu reprend', () async {
    final h = await _Harness.start(
      before: (root) {
        File('${root.path}/accounts/a/downloads.json').writeAsStringSync(
          jsonEncode({
            'version': 1,
            'downloads': {
              'movie:1': {
                'name': 'Film 1',
                'extension': 'mkv',
                'size': 1000,
                'received': 100,
                'status': 'running',
              },
            },
          }),
        );
        File('${root.path}/downloads/a/movie-1.mkv.part')
          ..createSync(recursive: true)
          ..writeAsBytesSync(_source.sublist(0, 400));
      },
    );

    await h.until(() => h.status('1') == DownloadStatus.ready);

    expect(h.server.ranges, ['bytes=400-']);
    expect(h.video('a', 'movie-1.mkv').readAsBytesSync(), _source);
  });

  test('pause, puis reprise où on en était', () async {
    final server = VideoServer(_source, cutAt: 500, hangAtCut: true);
    final h = await _Harness.start(server: server);
    await h.notifier.add([_movie('1'), _movie('2')]);
    await server.reachedCut;

    await h.notifier.pause('movie:1');

    expect(h.status('1'), DownloadStatus.paused);
    final part = h.video('a', 'movie-1.mkv.part');
    final kept = part.lengthSync();
    expect(kept, greaterThan(0));
    expect(h.entries['movie:1']!.received, kept);
    server.cutAt = null;
    await h.until(() => h.status('2') == DownloadStatus.ready);

    await h.notifier.resume('movie:1');
    await h.until(() => h.status('1') == DownloadStatus.ready);
    expect(server.ranges.last, 'bytes=$kept-');
    expect(h.video('a', 'movie-1.mkv').readAsBytesSync(), _source);
  });

  test('annuler efface le fichier partiel et passe au suivant', () async {
    final server = VideoServer(_source, cutAt: 500, hangAtCut: true);
    final h = await _Harness.start(server: server);
    await h.notifier.add([_movie('1'), _movie('2')]);
    await server.reachedCut;

    server.cutAt = null;
    await h.notifier.remove('movie:1');

    expect(h.entries.containsKey('movie:1'), isFalse);
    expect(h.video('a', 'movie-1.mkv.part').existsSync(), isFalse);
    await h.until(() => h.status('2') == DownloadStatus.ready);
  });

  test('supprimer un fichier prêt, puis tout supprimer', () async {
    final h = await _Harness.start();
    await h.notifier.add([_movie('1'), _movie('2')]);
    await h.until(() => h.status('2') == DownloadStatus.ready);

    await h.notifier.remove('movie:1');
    expect(h.video('a', 'movie-1.mkv').existsSync(), isFalse);
    expect(h.status('2'), DownloadStatus.ready);

    await h.notifier.removeAll();
    expect(h.entries, isEmpty);
    expect(h.video('a', 'movie-2.mkv').existsSync(), isFalse);
    expect(
      DownloadsStore(
        File('${h.root.path}/accounts/a/downloads.json'),
        Directory('${h.root.path}/downloads/a'),
      ).load(),
      isEmpty,
    );
  });

  test('changer de compte arrête la file du compte quitté', () async {
    final server = VideoServer(_source, cutAt: 500, hangAtCut: true);
    final h = await _Harness.start(server: server);
    await h.notifier.add([_movie('1')]);
    await server.reachedCut;

    await h.container.read(accountsProvider.notifier).activate('b');
    await h.until(() => h.entries.isEmpty);

    // Transfert arrêté : fichier fermé, effaçable.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final part = h.video('a', 'movie-1.mkv.part');
    expect(part.lengthSync(), greaterThan(0));
    part.deleteSync();
    // Le compte b a sa propre file, vide.
    expect(h.container.read(downloadsProvider).entries, isEmpty);
  });

  test('compte supprimé pendant un téléchargement : dossier effacé', () async {
    final server = VideoServer(_source, cutAt: 500, hangAtCut: true);
    final h = await _Harness.start(server: server);
    await h.notifier.add([_movie('1')]);
    await server.reachedCut;

    await h.container.read(accountsProvider.notifier).remove('a');

    expect(Directory('${h.root.path}/downloads/a').existsSync(), isFalse);
    expect(Directory('${h.root.path}/accounts/a').existsSync(), isFalse);
  });

  group('erreurs', () {
    test(
      'coupures répétées : tentatives bornées, puis échec relançable',
      () async {
        final server = VideoServer(_source, cutAt: 300);
        final h = await _Harness.start(server: server);
        server.cutAfterEachRequest = true;

        await h.notifier.add([_movie('1')]);
        await h.until(() => h.status('1') == DownloadStatus.failed);

        // Un essai et deux nouvelles tentatives, chacune reprend.
        expect(server.ranges, hasLength(3));
        expect(server.ranges.skip(1), everyElement(startsWith('bytes=')));
        expect(h.entries['movie:1']!.error, 'Connexion interrompue');

        server.cutAt = null;
        await h.notifier.resume('movie:1');
        await h.until(() => h.status('1') == DownloadStatus.ready);
        expect(h.video('a', 'movie-1.mkv').readAsBytesSync(), _source);
      },
    );

    test('refus du serveur : échec sans nouvelle tentative', () async {
      final server = VideoServer(_source, status: 404);
      final h = await _Harness.start(server: server);

      await h.notifier.add([_movie('1'), _movie('2')]);
      await h.until(() => h.status('2') == DownloadStatus.failed);

      expect(server.ranges, hasLength(2));
      expect(h.entries['movie:1']!.error, 'Introuvable sur le serveur (404)');
    });

    test('refus pendant une lecture : attend la sortie du lecteur', () async {
      final server = VideoServer(_source, status: 403);
      final h = await _Harness.start(server: server);
      final holds = h.container.read(downloadHoldsProvider.notifier);
      holds.streaming = true;

      await h.notifier.add([_movie('1')]);
      await h.until(
        () => h.container
            .read(downloadHoldsProvider)
            .reasons
            .contains(DownloadHold.playback),
      );
      expect(h.status('1'), DownloadStatus.queued);
      expect(server.ranges, hasLength(1));

      server.status = null;
      holds.streaming = false;
      await h.until(() => h.status('1') == DownloadStatus.ready);
    });

    test('refus, puis lecteur fermé avant la pause : la file repart', () async {
      final server = VideoServer(_source, status: 403);
      final h = await _Harness.start(server: server);
      final holds = h.container.read(downloadHoldsProvider.notifier);
      holds.streaming = true;
      // Le lecteur se ferme pendant l'écriture du manifeste qui suit le
      // refus, avant la pause de la file.
      h.container.listen(downloadsProvider, (previous, next) {
        if (previous?.entries['movie:1']?.status == DownloadStatus.running &&
            next.entries['movie:1']?.status == DownloadStatus.queued) {
          server.status = null;
          holds.streaming = false;
        }
      });

      await h.notifier.add([_movie('1')]);
      await h.until(() => h.status('1') == DownloadStatus.ready);
      expect(h.container.read(downloadHoldsProvider).reasons, isEmpty);
    });

    test(
      'refus pendant une lecture : la suite de la file attend aussi',
      () async {
        final server = VideoServer(_source, status: 403);
        final h = await _Harness.start(server: server);
        h.container.read(downloadHoldsProvider.notifier).streaming = true;

        await h.notifier.add([_movie('1'), _movie('2')]);
        await h.until(
          () => h.container
              .read(downloadHoldsProvider)
              .reasons
              .contains(DownloadHold.playback),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(h.status('1'), DownloadStatus.queued);
        expect(h.status('2'), DownloadStatus.queued);
        expect(server.ranges, hasLength(1), reason: 'rien ne repart');
      },
    );

    test('lecteur refusé pendant un téléchargement : pause, lecture, reprise '
        'à la sortie (D-036)', () async {
      final server = VideoServer(_source, cutAt: 500, hangAtCut: true);
      final h = await _Harness.start(server: server);
      final holds = h.container.read(downloadHoldsProvider.notifier);
      await h.notifier.add([_movie('1')]);
      await server.reachedCut;
      expect(h.notifier.downloading, isTrue);

      var refused = true;
      final source = await openContent(
        file: null,
        local: (_) => fail('pas de fichier'),
        stream: () async => PlayRequest(
          title: 'Autre',
          url: Uri.parse('http://serveur.test/x/9.mkv'),
          userAgent: 'ua',
        ),
        open: (_) async {
          // Le faux serveur refuse un 2e flux tant que le téléchargement
          // tient la connexion.
          if (refused && h.notifier.downloading) throw const PlaybackFailed();
          refused = false;
        },
        dropFile: () => fail('rien à retirer'),
        streaming: (open) => holds.streaming = open,
        downloading: () => h.notifier.downloading,
        pauseDownloads: () => holds.pauseAll(DownloadHold.playback),
      );
      expect(source, PlaySource.stream);
      await h.until(() => h.status('1') == DownloadStatus.queued);
      expect(h.notifier.downloading, isFalse);

      // Sortie du lecteur.
      server.cutAt = null;
      holds.streaming = false;
      await h.until(() => h.status('1') == DownloadStatus.ready);
    });

    test('lecture locale pendant un téléchargement : rien en pause', () async {
      final server = VideoServer(_source, cutAt: 500, hangAtCut: true);
      final h = await _Harness.start(server: server);
      final holds = h.container.read(downloadHoldsProvider.notifier);
      await h.notifier.add([_movie('1')]);
      await server.reachedCut;
      final file = File('${h.root.path}${Platform.pathSeparator}local.mkv')
        ..writeAsStringSync('vidéo');

      final source = await openContent(
        file: file,
        local: (file) => PlayRequest(
          title: 'Local',
          url: Uri.file(file.path),
          userAgent: '',
        ),
        stream: () => fail('le serveur ne doit pas être appelé'),
        open: (_) async {},
        dropFile: () => fail('rien à retirer'),
        streaming: (open) => holds.streaming = open,
        downloading: () => h.notifier.downloading,
        pauseDownloads: () => fail('rien à mettre en pause'),
      );
      expect(source, PlaySource.local);
      expect(h.container.read(downloadHoldsProvider).reasons, isEmpty);
      expect(h.status('1'), DownloadStatus.running);
    });

    test('place insuffisante : échec avec la raison', () async {
      final h = await _Harness.start(
        freeSpace: freeSpaceProvider.overrideWithValue((_) async => 10),
      );

      await h.notifier.add([_movie('1')]);
      await h.until(() => h.status('1') == DownloadStatus.failed);

      expect(h.entries['movie:1']!.error, 'Espace disque insuffisant');
    });
  });

  group('Effacer une fois vu (D-037)', () {
    Future<_Harness> ready({bool setting = true}) async {
      final h = await _Harness.start();
      await h.container
          .read(appSettingsProvider.notifier)
          .setDeleteWatched(setting);
      await h.notifier.add([_movie('1'), _movie('2')]);
      await h.until(() => h.status('2') == DownloadStatus.ready);
      return h;
    }

    LibraryNotifier library(_Harness h) =>
        h.container.read(libraryProvider.notifier);

    test('« Marquer comme vu » : vidéo effacée, les autres restent', () async {
      final h = await ready();
      await library(h).setWatched(_movie('1'), watched: true);
      await h.until(() => h.status('1') == null);
      await h.until(() => !h.video('a', 'movie-1.mkv').existsSync());
      expect(h.status('2'), DownloadStatus.ready);
    });

    test('réglage désactivé : la vidéo reste', () async {
      final h = await ready(setting: false);
      await library(h).setWatched(_movie('1'), watched: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.status('1'), DownloadStatus.ready);
    });

    test('vu pendant la lecture : effacée à la sortie du lecteur', () async {
      final h = await ready();
      h.notifier.playerOpened();
      await library(h).saveProgress(
        _movie('1'),
        position: const Duration(minutes: 95),
        duration: const Duration(minutes: 100),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.status('1'), DownloadStatus.ready, reason: 'fichier ouvert');
      expect(h.video('a', 'movie-1.mkv').existsSync(), isTrue);

      h.notifier.playerClosed();
      await h.until(() => h.status('1') == null);
      await h.until(() => !h.video('a', 'movie-1.mkv').existsSync());
    });

    test('changement de compte : la vidéo vue sur b reste', () async {
      final h = await _Harness.start();
      final accounts = h.container.read(accountsProvider.notifier);
      // Film prêt sur les deux comptes, vu sur b seulement, réglage
      // désactivé pendant la préparation.
      await accounts.activate('b');
      await h.notifier.add([_movie('1')]);
      await h.until(() => h.status('1') == DownloadStatus.ready);
      await library(h).setWatched(_movie('1'), watched: true);
      await accounts.activate('a');
      await h.until(() => h.status('1') == null);
      await h.notifier.add([_movie('1')]);
      await h.until(() => h.status('1') == DownloadStatus.ready);
      await h.container
          .read(appSettingsProvider.notifier)
          .setDeleteWatched(true);

      // Non vu sur a, vu sur b : ce n'est pas un passage à « vu ».
      await accounts.activate('b');
      await h.until(() => h.status('1') == DownloadStatus.ready);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.status('1'), DownloadStatus.ready);
      expect(h.video('b', 'movie-1.mkv').existsSync(), isTrue);
      expect(h.video('a', 'movie-1.mkv').existsSync(), isTrue);
    });

    test('déjà vu avant le téléchargement : la vidéo reste', () async {
      final h = await _Harness.start();
      await h.container
          .read(appSettingsProvider.notifier)
          .setDeleteWatched(true);
      await library(h).setWatched(_movie('1'), watched: true);
      await h.notifier.add([_movie('1')]);
      await h.until(() => h.status('1') == DownloadStatus.ready);
      await library(h).saveProgress(
        _movie('1'),
        position: const Duration(minutes: 99),
        duration: const Duration(minutes: 100),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.status('1'), DownloadStatus.ready);
    });
  });

  group('pauses de toute la file', () {
    test('pauseAll arrête le téléchargement, resumeAll le reprend', () async {
      final server = VideoServer(_source, cutAt: 500, hangAtCut: true);
      final h = await _Harness.start(server: server);
      await h.notifier.add([_movie('1')]);
      await server.reachedCut;
      final holds = h.container.read(downloadHoldsProvider.notifier);

      holds.pauseAll(DownloadHold.playback);
      await h.until(
        () =>
            h.status('1') == DownloadStatus.queued &&
            h.entries['movie:1']!.received > 0,
      );
      final kept = h.entries['movie:1']!.received;
      server.cutAt = null;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.ranges, hasLength(1), reason: 'rien ne repart');

      holds.resumeAll(DownloadHold.playback);
      await h.until(() => h.status('1') == DownloadStatus.ready);
      expect(server.ranges.last, 'bytes=$kept-');
    });

    test('pause juste à la fin d\'un téléchargement : il reste prêt', () async {
      final h = await _Harness.start();
      final holds = h.container.read(downloadHoldsProvider.notifier);
      // La pause arrive dès que l'entrée est prête, avant que la file ne
      // passe au suivant.
      h.container.listen(downloadsProvider, (_, next) {
        if (next.entries['movie:1']?.status == DownloadStatus.ready) {
          holds.pauseAll(DownloadHold.background);
        }
      });

      await h.notifier.add([_movie('1')]);
      await h.until(
        () => h.container
            .read(downloadHoldsProvider)
            .reasons
            .contains(DownloadHold.background),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.status('1'), DownloadStatus.ready);

      holds.resumeAll(DownloadHold.background);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.status('1'), DownloadStatus.ready);
      expect(h.server.ranges, [null], reason: 'pas téléchargé deux fois');
    });

    test('Android : app quittée, pause ; retour, reprise', () async {
      final binding = TestWidgetsFlutterBinding.instance;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final h = await _Harness.start(background: true);
      h.container.read(downloadHoldsProvider);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await h.notifier.add([_movie('1')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.status('1'), DownloadStatus.queued);
      expect(h.server.ranges, isEmpty);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await h.until(() => h.status('1') == DownloadStatus.ready);
    });

    test(
      'Wi-Fi seulement : rien ne part avant de connaître le réseau',
      () async {
        final network = StreamController<bool>();
        addTearDown(network.close);
        final h = await _Harness.start(
          network: () => network.stream,
          before: (root) => File('${root.path}/accounts/a/downloads.json')
              .writeAsStringSync(
                jsonEncode({
                  'downloads': {
                    'movie:1': {
                      'name': 'Film 1',
                      'extension': 'mkv',
                      'status': 'queued',
                    },
                  },
                }),
              ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(h.server.ranges, isEmpty);

        network.add(true);
        await h.until(
          () => h.container.read(downloadHoldsProvider).waitingForWifi,
        );
        expect(h.server.ranges, isEmpty);

        network.add(false);
        await h.until(() => h.status('1') == DownloadStatus.ready);
      },
    );

    test('Wi-Fi seulement : la file attend sur réseau mobile', () async {
      final h = await _Harness.start(mobileOnly: true);
      await h.until(
        () => h.container.read(downloadHoldsProvider).waitingForWifi,
      );

      await h.notifier.add([_movie('1')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.server.ranges, isEmpty);

      await h.container.read(appSettingsProvider.notifier).setWifiOnly(false);
      await h.until(() => h.status('1') == DownloadStatus.ready);
      expect(h.container.read(downloadHoldsProvider).waitingForWifi, isFalse);
    });
  });

  test('réseau mobile seul : Wi-Fi ou Ethernet laissent passer', () {
    expect(isMobileOnly([ConnectivityResult.mobile]), isTrue);
    expect(
      isMobileOnly([ConnectivityResult.mobile, ConnectivityResult.wifi]),
      isFalse,
    );
    expect(isMobileOnly([ConnectivityResult.ethernet]), isFalse);
    expect(isMobileOnly([ConnectivityResult.none]), isFalse);
  });
}
