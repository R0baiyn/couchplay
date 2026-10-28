import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:couchplay/update/updater.dart';
import 'package:couchplay/update/windows_installer.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

/// Installation simulée : retient ce qui lui est confié.
final class _FakeInstaller implements Installer {
  _FakeInstaller(this.workDir, {this.pending = false});

  @override
  final Directory workDir;

  /// Réponse de [installPending].
  final bool pending;

  /// Contenu de chaque fichier préparé.
  final received = <String>[];

  @override
  String get assetSuffix => '-windows-portable.zip';

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
  Future<bool> installPending(String current) async => pending;
}

void main() {
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
    Map<String, Object?> release({String tag = 'v0.1.1'}) => {
      'tag_name': tag,
      'body': '- Nouvelle icône\n',
      'assets': [
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
