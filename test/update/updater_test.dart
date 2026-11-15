import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:couchplay/update/android_installer.dart';
import 'package:couchplay/update/linux_installer.dart';
import 'package:couchplay/update/release_signature.dart';
import 'package:couchplay/update/updater.dart';
import 'package:couchplay/update/windows_installer.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

/// Installation simulée : retient ce qui lui est confié.
final class _FakeInstaller implements Installer {
  _FakeInstaller(
    this.workDir, {
    this.pending = false,
    this.pendingError,
    this.signed = false,
  });

  @override
  final Directory workDir;

  /// Réponse de [installPending].
  final bool pending;

  /// Levée par [installPending] à la place de sa réponse.
  final Exception? pendingError;

  /// Contenu de chaque fichier préparé.
  final received = <String>[];

  @override
  final bool signed;

  @override
  String get assetSuffix => '-windows-portable.zip';

  @override
  Future<void> Function(Uri page)? get openPage => null;

  @override
  String get later => 'plus tard';

  @override
  String get packageName => 'update.zip';

  @override
  Future<void> prepared(Update update, File package) async =>
      received.add(await package.readAsString());

  @override
  Future<void> installNow() async {}

  @override
  Future<bool> installPending(String current) async {
    if (pendingError case final error?) throw error;
    return pending;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isNewer', () {
    test('compare chaque numéro, pas le texte', () {
      expect(isNewer('0.1.10', '0.1.9'), isTrue);
      expect(isNewer('0.1.9', '0.1.10'), isFalse);
      expect(isNewer('1.0.0', '0.9.9'), isTrue);
    });

    test('ignore le préfixe v et le suffixe +build', () {
      expect(isNewer('v0.1.1', '0.1.0+1'), isTrue);
      expect(isNewer('v0.1.0', '0.1.0+7'), isFalse);
    });

    test('une version illisible n\'est jamais plus récente', () {
      expect(isNewer('latest', '0.1.0'), isFalse);
      expect(isNewer('v0.2', '0.1.0'), isFalse);
    });
  });

  group('updateFrom', () {
    Map<String, Object?> release({
      String tag = 'v0.1.1',
      String page = 'https://github.com/R0baiyn/couchplay/releases/tag/v0.1.1',
    }) => {
      'tag_name': tag,
      'body': '- Nouvelle icône\n',
      'html_url': page,
      'assets': [
        {
          'name': 'couchplay-0.1.1-linux-x64.tar.gz',
          'browser_download_url': 'https://github.com/R0baiyn/couchplay/releases/download/v0.1.1/couchplay-0.1.1-linux-x64.tar.gz',
          'size': 40,
        },
        {
          'name': 'couchplay-0.1.1-windows-portable.zip',
          'browser_download_url': 'https://github.com/R0baiyn/couchplay/releases/download/v0.1.1/couchplay-0.1.1-windows-portable.zip',
          'size': 30,
        },
        {
          'name': 'couchplay-0.1.1-windows-setup.exe',
          'browser_download_url': 'https://github.com/R0baiyn/couchplay/releases/download/v0.1.1/couchplay-0.1.1-windows-setup.exe',
          'size': 20,
        },
        {
          'name': 'couchplay-0.1.1-android-armv7.apk',
          'browser_download_url': 'https://github.com/R0baiyn/couchplay/releases/download/v0.1.1/couchplay-0.1.1-android-armv7.apk',
          'size': 28,
        },
        {
          'name': 'couchplay-0.1.1-android-arm64.apk',
          'browser_download_url': 'https://github.com/R0baiyn/couchplay/releases/download/v0.1.1/couchplay-0.1.1-android-arm64.apk',
          'size': 31,
        },
      ],
    };

    const setup = '-windows-setup.exe';

    test('installée : l\'installateur', () {
      final update = updateFrom(release(), current: '0.1.0', suffix: setup)!;
      expect(update.version, '0.1.1');
      expect(update.notes, '- Nouvelle icône');
      expect(update.asset.path, endsWith('-windows-setup.exe'));
      expect(update.size, 20);
    });

    test('portable : le zip', () {
      final update = updateFrom(
        release(),
        current: '0.1.0',
        suffix: '-windows-portable.zip',
      )!;
      expect(update.asset.path, endsWith('-windows-portable.zip'));
      expect(update.size, 30);
    });

    test('Android : l\'APK de son architecture', () {
      Update? forAbi(Abi abi) => updateFrom(
        release(),
        current: '0.1.0',
        suffix: androidAssetSuffix(abi)!,
      );
      expect(forAbi(Abi.androidArm64)!.asset.path, endsWith('-arm64.apk'));
      expect(forAbi(Abi.androidArm64)!.size, 31);
      expect(forAbi(Abi.androidArm)!.asset.path, endsWith('-armv7.apk'));
      // Pas d'APK publié pour un émulateur x86_64 : pas de mise à jour.
      expect(androidAssetSuffix(Abi.androidX64), isNull);
    });

    test("Linux : l'archive et la page de la release", () {
      final update = updateFrom(
        release(),
        current: '0.1.0',
        suffix: LinuxInstaller().assetSuffix,
      )!;
      expect(update.asset.path, endsWith('-linux-x64.tar.gz'));
      expect(update.size, 40);
      expect(
        update.page,
        Uri.parse('https://github.com/R0baiyn/couchplay/releases/tag/v0.1.1'),
      );
    });

    test('page de release hors de GitHub en HTTPS : ignorée', () {
      Uri? page(String url) => updateFrom(
        release(page: url),
        current: '0.1.0',
        suffix: setup,
      )!.page;
      expect(page('https://example.com/releases/tag/v0.1.1'), isNull);
      expect(page('http://github.com/R0baiyn/couchplay'), isNull);
      expect(page('file:///etc/passwd'), isNull);
    });

    test('rien si la version n\'est pas plus récente', () {
      expect(updateFrom(release(), current: '0.1.1', suffix: setup), isNull);
    });

    test('rien si le fichier vient d\'un autre hôte', () {
      final json = release();
      for (final asset in json['assets'] as List) {
        (asset as Map)['browser_download_url'] = 'https://example.com/x.exe';
      }
      expect(updateFrom(json, current: '0.1.0', suffix: setup), isNull);
    });

    test('la liste et sa signature ne passent jamais pour un fichier', () {
      // Une 1.2.1, qui ne vérifie rien, doit continuer à trouver son fichier.
      final json = release();
      json['assets'] = [
        for (final name in [sumsName, signatureName])
          {
            'name': name,
            'browser_download_url':
                'https://github.com/R0baiyn/couchplay/releases/download/v0.1.1/$name',
            'size': 10,
          },
        ...json['assets'] as List,
      ];
      for (final suffix in [
        setup,
        '-windows-portable.zip',
        '-android-arm64.apk',
        '-android-armv7.apk',
        '-linux-x64.tar.gz',
      ]) {
        final update = updateFrom(json, current: '0.1.0', suffix: suffix)!;
        expect(update.asset.path, endsWith(suffix));
      }
    });

    test('réponse inattendue : rien, sans exception', () {
      expect(updateFrom(null, current: '0.1.0', suffix: setup), isNull);
      expect(
        updateFrom({'tag_name': 'v9.0.0'}, current: '0.1.0', suffix: setup),
        isNull,
      );
    });
  });

  group('WindowsInstaller.forApp', () {
    late Directory app;
    setUp(() => app = Directory.systemTemp.createTempSync('couchplay-app'));
    tearDown(() => app.deleteSync(recursive: true));

    WindowsInstaller? installer() => WindowsInstaller.forApp(app);

    test('marqueur du zip : portable', () {
      File('${app.path}\\portable').createSync();
      expect(installer()?.portable, isTrue);
      expect(installer()?.assetSuffix, '-windows-portable.zip');
    });

    test('désinstalleur d\'Inno Setup : installée', () {
      File('${app.path}\\unins000.exe').createSync();
      expect(installer()?.portable, isFalse);
      expect(installer()?.assetSuffix, '-windows-setup.exe');
    });

    test('ni l\'un ni l\'autre (build local) : pas de mise à jour', () {
      expect(installer(), isNull);
    });

    test(
      'au démarrage, un fichier préparé sans vérification n\'est pas lancé',
      () async {
        // Comme après « Plus tard » dans une version qui ne vérifiait rien.
        final work = Directory('${app.path}\\couchplay-update')..createSync();
        File('${work.path}\\update.exe').writeAsStringSync('exe');
        final windows = WindowsInstaller(
          portable: false,
          appDir: app,
          workDir: work,
        );
        expect(await windows.installPending('0.1.0'), isFalse);
        expect(work.listSync(), hasLength(1), reason: 'rien de lancé');
      },
    );
  });

  test('seul Linux ouvre la page de la release au lieu d\'installer', () {
    final temp = Directory.systemTemp;
    expect(LinuxInstaller().openPage, isNotNull);
    expect(WindowsInstaller(portable: true, appDir: temp).openPage, isNull);
    expect(
      AndroidInstaller(
        assetSuffix: '-android-arm64.apk',
        workDir: temp,
      ).openPage,
      isNull,
    );
  });

  group('prepare', () {
    late Directory work;
    setUp(() => work = Directory.systemTemp.createTempSync('couchplay-test'));
    tearDown(() {
      try {
        work.deleteSync(recursive: true);
      } on FileSystemException {
        // Fichier encore ouvert par un téléchargement annulé (Windows) : le
        // dossier temporaire reste, sans effet sur les tests.
      }
    });

    final update = Update(
      version: '0.1.1',
      notes: '',
      asset: Uri.parse('https://github.com/R0baiyn/couchplay/x.zip'),
      size: 3,
    );

    late _FakeInstaller installer;

    Updater updater(FakeAdapter adapter) => Updater(
      version: '0.1.0',
      installer: installer = _FakeInstaller(
        Directory('${work.path}${Platform.pathSeparator}update'),
      ),
      adapter: adapter,
    );

    test('fichier complet : confié à l\'installation', () async {
      await updater(FakeAdapter.replying('abc')).prepare(update);
      expect(installer.received, ['abc']);
    });

    test('une redirection vers un autre hôte est refusée', () async {
      final adapter = FakeAdapter(
        (_) async => ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['https://example.com/x.zip'],
          },
        ),
      );
      await expectLater(
        updater(adapter).prepare(update),
        throwsA(isA<HttpException>()),
      );
      expect(adapter.calls, 1);
    });

    test('plus gros qu\'annoncé : coupé sans attendre la fin', () async {
      // 6 octets pour 3 annoncés, et le serveur ne termine jamais : seule la
      // coupure fait aboutir le test.
      final body = StreamController<Uint8List>()..add(Uint8List(6));
      addTearDown(body.close);
      await expectLater(
        updater(FakeAdapter((_) async => ResponseBody(body.stream, 200)))
            .prepare(update),
        throwsA(isA<HttpException>()),
      );
    });

    test('« Annuler » arrête un téléchargement qui traîne', () async {
      // Le serveur envoie un octet puis plus rien, sans fermer.
      final body = StreamController<Uint8List>()..add(Uint8List(1));
      addTearDown(body.close);
      final subject = updater(
        FakeAdapter((_) async => ResponseBody(body.stream, 200)),
      );
      final done = subject.prepare(update);
      // Annuler une fois le premier octet reçu : le téléchargement a commencé.
      for (var i = 0; i < 250 && subject.progress.value == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(subject.progress.value, greaterThan(0));
      subject.cancel();
      await expectLater(
        done,
        throwsA(
          isA<DioException>().having(CancelToken.isCancel, 'annulé', true),
        ),
      );
    });

    test('redirection GitHub suivie, puis fichier tronqué refusé', () async {
      final adapter = FakeAdapter(
        (options) async => options.uri.host == 'github.com'
            ? ResponseBody.fromString(
                '',
                302,
                headers: {
                  'location': [
                    'https://release-assets.githubusercontent.com/x',
                  ],
                },
              )
            : ResponseBody.fromString('ab', 200),
      );
      await expectLater(
        updater(adapter).prepare(update),
        throwsA(isA<HttpException>()),
      );
      expect(adapter.calls, 2);
    });

    test('une seule préparation par version', () async {
      // Le serveur ne répond jamais : la préparation reste en cours.
      final body = StreamController<Uint8List>();
      addTearDown(body.close);
      final adapter = FakeAdapter((_) async => ResponseBody(body.stream, 200));
      final subject = updater(adapter);
      final first = subject.prepare(update);
      final second = subject.prepare(update);
      expect(identical(first, second), isTrue);
      for (var i = 0; i < 250 && adapter.calls == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(adapter.calls, 1);
      subject.cancel();
      await expectLater(first, throwsA(isA<DioException>()));
    });

    test('un échec se retente au prochain appel', () async {
      final adapter = FakeAdapter.replying('', status: 404);
      final subject = updater(adapter);
      for (var i = 0; i < 2; i++) {
        await expectLater(subject.prepare(update), throwsA(anything));
      }
      expect(adapter.calls, 2);
    });
  });

  group('prepare signé (Windows)', () {
    late Directory work;
    late Directory updateDir;
    late List<int> seed;
    late List<int> publicKey;
    late _FakeInstaller installer;
    setUp(() async {
      work = Directory.systemTemp.createTempSync('couchplay-signed');
      updateDir = Directory('${work.path}${Platform.pathSeparator}update');
      // Clé de test tirée à chaque exécution, jamais écrite en dur.
      final random = Random.secure();
      seed = [for (var i = 0; i < keyLength; i++) random.nextInt(256)];
      publicKey = await publicKeyOf(seed);
    });
    tearDown(() => work.deleteSync(recursive: true));

    const name = 'couchplay-0.1.1-windows-portable.zip';
    Update updateOf(String file) => Update(
      version: '0.1.1',
      notes: '',
      asset: Uri.parse(
        'https://github.com/R0baiyn/couchplay/releases/download/v0.1.1/$file',
      ),
      size: 3,
    );
    final update = updateOf(name);

    /// Liste de la release, avec la somme de [content] pour [listed].
    Future<(String, String)> signedList(
      String content, {
      String listed = name,
      List<int>? key,
    }) async {
      final sums = formatSums({
        listed: sha256.convert(utf8.encode(content)).toString(),
        'couchplay-0.1.1-windows-setup.exe': '0' * 64,
      });
      return (sums, await signBytes(utf8.encode(sums), key ?? seed));
    }

    /// Répond comme la release : la liste, sa signature et le fichier.
    FakeAdapter release({
      String? sums,
      String? signature,
      String package = 'abc',
    }) => FakeAdapter((options) async {
      final body = switch (options.uri.pathSegments.last) {
        sumsName => sums,
        signatureName => signature,
        _ => package,
      };
      return ResponseBody.fromString(body ?? '', body == null ? 404 : 200);
    });

    Updater updater(FakeAdapter adapter) => Updater(
      version: '0.1.0',
      installer: installer = _FakeInstaller(updateDir, signed: true),
      adapter: adapter,
      publicKey: publicKey,
    );

    Future<void> expectRefused(FakeAdapter adapter, {Update? of}) async {
      await expectLater(
        updater(adapter).prepare(of ?? update),
        throwsA(isA<UnsignedUpdate>()),
      );
      expect(installer.received, isEmpty);
      expect(updateDir.existsSync(), isFalse, reason: 'fichier effacé');
    }

    test('fichier dans la liste signée : confié à l\'installation', () async {
      final (sums, signature) = await signedList('abc');
      final adapter = release(sums: sums, signature: signature);
      await updater(adapter).prepare(update);
      expect(installer.received, ['abc']);
      expect(adapter.calls, 3);
    });

    test('fichier remplacé (même taille) : refusé et effacé', () async {
      final (sums, signature) = await signedList('abc');
      await expectRefused(
        release(sums: sums, signature: signature, package: 'abd'),
      );
    });

    test('liste modifiée après signature : refusée', () async {
      final (_, signature) = await signedList('abc');
      final (forged, _) = await signedList('abd');
      await expectRefused(
        release(sums: forged, signature: signature, package: 'abd'),
      );
    });

    test('signée par une autre clé : refusée', () async {
      final (sums, signature) = await signedList(
        'abc',
        key: List.filled(keyLength, 7),
      );
      await expectRefused(release(sums: sums, signature: signature));
    });

    test('signature illisible : refusée', () async {
      final (sums, _) = await signedList('abc');
      await expectRefused(release(sums: sums, signature: 'ÿþ'));
    });

    test('fichier absent de la liste : refusé', () async {
      final (sums, signature) = await signedList(
        'abc',
        listed: 'couchplay-0.1.1-windows-other.zip',
      );
      await expectRefused(release(sums: sums, signature: signature));
    });

    test('fichier signé d\'une autre version : refusé', () async {
      // Une release 0.1.1 qui ressert le zip signé de la 0.1.0.
      const old = 'couchplay-0.1.0-windows-portable.zip';
      final (sums, signature) = await signedList('abc', listed: old);
      await expectRefused(
        release(sums: sums, signature: signature),
        of: updateOf(old),
      );
    });

    test('signature absente : échec avant le gros téléchargement', () async {
      final (sums, _) = await signedList('abc');
      final adapter = release(sums: sums);
      await expectLater(
        updater(adapter).prepare(update),
        throwsA(isA<DioException>()),
      );
      expect(installer.received, isEmpty);
      expect(adapter.calls, 2, reason: 'fichier jamais demandé');
    });

    test('erreur en route : aucun fichier non vérifié ne reste', () async {
      final (sums, signature) = await signedList('abc');
      // Le fichier arrive tronqué après la liste et sa signature.
      final adapter = FakeAdapter((options) async {
        final body = switch (options.uri.pathSegments.last) {
          sumsName => sums,
          signatureName => signature,
          _ => 'ab',
        };
        return ResponseBody.fromString(body, 200);
      });
      await expectLater(
        updater(adapter).prepare(update),
        throwsA(isA<HttpException>()),
      );
      expect(updateDir.existsSync(), isFalse);
    });

    test('liste démesurée : coupée', () async {
      final (_, signature) = await signedList('abc');
      await expectLater(
        updater(release(sums: 'a' * (128 * 1024), signature: signature))
            .prepare(update),
        throwsA(isA<HttpException>()),
      );
      expect(installer.received, isEmpty);
    });
  });

  group('AndroidInstaller', () {
    late Directory work;
    late List<String> calls;
    const channel = MethodChannel('couchplay/update');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    setUp(() {
      work = Directory.systemTemp.createTempSync('couchplay-apk');
      calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      if (work.existsSync()) work.deleteSync(recursive: true);
    });

    AndroidInstaller installer() =>
        AndroidInstaller(assetSuffix: '-android-arm64.apk', workDir: work);

    /// Comme après un téléchargement « Plus tard » de la 0.2.1.
    Future<void> prepare() async {
      final apk = File('${work.path}/couchplay.apk')..writeAsStringSync('apk');
      await installer().prepared(
        Update(version: '0.2.1', notes: '', asset: Uri(), size: 3),
        apk,
      );
    }

    test(
      'remise à plus tard : l\'installateur s\'ouvre au démarrage',
      () async {
        await prepare();
        expect(await installer().installPending('0.2.0'), isTrue);
        expect(calls, ['install']);
      },
    );

    test('déjà installée : rien, et le dossier est vidé', () async {
      await prepare();
      expect(await installer().installPending('0.2.1'), isFalse);
      expect(calls, isEmpty);
      expect(work.existsSync(), isFalse);
    });

    test('téléchargement inachevé (sans version) : rien', () async {
      File('${work.path}/couchplay.apk').writeAsStringSync('ap');
      expect(await installer().installPending('0.2.0'), isFalse);
      expect(calls, isEmpty);
    });

    for (final version in ['', 'abc']) {
      test(
        'fichier version illisible (« $version ») : rien, dossier vidé',
        () async {
          File('${work.path}/couchplay.apk').writeAsStringSync('apk');
          File('${work.path}/version').writeAsStringSync(version);
          expect(await installer().installPending('0.2.0'), isFalse);
          expect(calls, isEmpty);
          expect(work.existsSync(), isFalse);
        },
      );
    }

    test('APK effacé avec le cache : rien', () async {
      await prepare();
      File('${work.path}/couchplay.apk').deleteSync();
      expect(await installer().installPending('0.2.0'), isFalse);
      expect(calls, isEmpty);
    });

    test('« Mettre à jour » ouvre l\'installateur', () async {
      await installer().installNow();
      expect(calls, ['install']);
    });
  });

  group('au démarrage', () {
    Future<Update?> startup(Updater updater) {
      final container = ProviderContainer(
        overrides: [updaterProvider.overrideWithValue(updater)],
      );
      addTearDown(container.dispose);
      return container.read(startupUpdateProvider.future);
    }

    test('hors ligne : pas de mise à jour, sans erreur', () async {
      final updater = Updater(
        version: '0.1.0',
        installer: _FakeInstaller(Directory.systemTemp),
        adapter: FakeAdapter.failing(DioExceptionType.connectionError),
      );
      expect(await startup(updater), isNull);
    });

    test(
      'une mise à jour remise à plus tard s\'installe, sans vérifier',
      () async {
        final adapter = FakeAdapter.replying('{}');
        final updater = Updater(
          version: '0.1.0',
          installer: _FakeInstaller(Directory.systemTemp, pending: true),
          adapter: adapter,
        );
        expect(await startup(updater), isNull);
        expect(adapter.calls, 0);
      },
    );

    test(
      'installateur introuvable : pas de mise à jour, sans erreur',
      () async {
        final updater = Updater(
          version: '0.1.0',
          installer: _FakeInstaller(
            Directory.systemTemp,
            pendingError: PlatformException(code: 'install'),
          ),
          adapter: FakeAdapter.replying('{}'),
        );
        expect(await startup(updater), isNull);
      },
    );
  });

  test('téléchargement : HTTPS chez GitHub seulement', () {
    expect(
      isAllowedDownload(Uri.parse('https://github.com/R0baiyn/couchplay')),
      isTrue,
    );
    expect(
      isAllowedDownload(
        Uri.parse('https://release-assets.githubusercontent.com/x'),
      ),
      isTrue,
    );
    expect(isAllowedDownload(Uri.parse('http://github.com/x')), isFalse);
    expect(
      isAllowedDownload(Uri.parse('https://github.com.evil.io/x')),
      isFalse,
    );
  });
}
