import 'dart:async';
import 'dart:io';

import 'package:couchplay/update/linux_installer.dart';
import 'package:couchplay/update/update_dialog.dart';
import 'package:couchplay/update/updater.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

/// Installation simulée : compte les installations, échoue sur demande.
final class _FakeInstaller implements Installer {
  _FakeInstaller(this.workDir, {this.fails = false});

  @override
  final Directory workDir;

  /// [installNow] lève l'erreur d'Android sans installateur.
  final bool fails;

  var installs = 0;
  var prepares = 0;

  @override
  String get assetSuffix => '-android-arm64.apk';

  @override
  String get later => 'au prochain démarrage de CouchPlay';

  @override
  String get packageName => 'couchplay.apk';

  @override
  Future<void> prepared(Update update, File package) async => prepares++;

  @override
  Future<void> installNow() async {
    installs++;
    if (fails) throw PlatformException(code: 'install');
  }

  @override
  Future<bool> installPending(String current) async => false;
}

void main() {
  late Directory work;
  setUp(() => work = Directory.systemTemp.createTempSync('couchplay-dialog'));
  tearDown(() {
    try {
      work.deleteSync(recursive: true);
    } on FileSystemException {
      // Fichier encore ouvert par un téléchargement annulé (Windows).
    }
  });

  final update = Update(
    version: '0.1.1',
    notes: 'Nouveautés',
    asset: Uri.parse('https://github.com/R0baiyn/couchplay/x.apk'),
    size: 3,
  );

  /// La fenêtre « Version 0.1.1 disponible », ouverte.
  Future<(Updater, _FakeInstaller)> open(
    WidgetTester tester, {
    bool fails = false,
    FakeAdapter? adapter,
  }) async {
    final installer = _FakeInstaller(
      Directory('${work.path}${Platform.pathSeparator}update'),
      fails: fails,
    );
    final updater = Updater(
      version: '0.1.0',
      installer: installer,
      adapter: adapter ?? FakeAdapter.replying('abc'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showUpdateDialog(context, updater, update),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('Version 0.1.1 disponible'), findsOneWidget);
    return (updater, installer);
  }

  /// Le téléchargement écrit un vrai fichier : il avance hors du temps
  /// simulé des tests, jusqu'à [done].
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 150 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue);
    await tester.pumpAndSettle();
  }

  testWidgets('« Mettre à jour » : installé, la progression se ferme', (
    tester,
  ) async {
    final (_, installer) = await open(tester);
    await tester.tap(find.text('Mettre à jour'));
    await tester.pump();
    expect(find.text('Téléchargement : 0 %'), findsOneWidget);

    await waitFor(tester, () => installer.installs > 0);
    expect(installer.installs, 1);
    expect(find.textContaining('Téléchargement'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('« Mettre à jour » : un échec ferme la progression et le dit', (
    tester,
  ) async {
    final (_, installer) = await open(tester, fails: true);
    await tester.tap(find.text('Mettre à jour'));
    await waitFor(tester, () => installer.installs > 0);
    expect(find.textContaining('Téléchargement'), findsNothing);
    expect(
      find.text('La mise à jour a échoué. Réessaie plus tard.'),
      findsOneWidget,
    );
  });

  testWidgets('« Annuler » : la progression se ferme, rien d\'installé', (
    tester,
  ) async {
    // Le serveur envoie un octet puis plus rien, sans fermer.
    final body = StreamController<Uint8List>()..add(Uint8List(1));
    addTearDown(body.close);
    final (updater, installer) = await open(
      tester,
      adapter: FakeAdapter((_) async => ResponseBody(body.stream, 200)),
    );
    await tester.tap(find.text('Mettre à jour'));
    await waitFor(tester, () => updater.progress.value > 0);

    await tester.tap(find.text('Annuler'));
    await waitFor(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
    expect(find.textContaining('Téléchargement'), findsNothing);
    expect(find.text('Mise à jour annulée.'), findsOneWidget);
    expect(installer.installs, 0);
  });

  testWidgets('« Plus tard » : téléchargée une fois, puis le message', (
    tester,
  ) async {
    final (_, installer) = await open(tester);
    await tester.tap(find.text('Plus tard'));
    await waitFor(tester, () => installer.prepares > 0);
    expect(installer.prepares, 1);
    expect(installer.installs, 0);
    expect(
      find.text(
        'Mise à jour prête : elle s\'installera au prochain démarrage '
        'de CouchPlay.',
      ),
      findsOneWidget,
    );
  });

  group('Linux', () {
    final page = Uri.parse(
      'https://github.com/R0baiyn/couchplay/releases/tag/v0.1.1',
    );

    /// La fenêtre ouverte sous Linux : [opened] reçoit chaque page ouverte.
    Future<void> openLinux(
      WidgetTester tester,
      List<Uri> opened, {
      Uri? releasePage,
    }) async {
      final updater = Updater(
        version: '0.1.0',
        installer: LinuxInstaller(open: (url) async => opened.add(url)),
        adapter: FakeAdapter((_) async => fail('aucun téléchargement')),
      );
      final linuxUpdate = Update(
        version: '0.1.1',
        notes: 'Nouveautés',
        asset: Uri.parse('https://github.com/R0baiyn/couchplay/x.tar.gz'),
        size: 3,
        page: releasePage,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showUpdateDialog(context, updater, linuxUpdate),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('Version 0.1.1 disponible'), findsOneWidget);
      expect(find.text('Nouveautés'), findsOneWidget);
      expect(find.text('Mettre à jour'), findsNothing);
    }

    testWidgets('« Ouvrir la page » : la release, sans téléchargement', (
      tester,
    ) async {
      final opened = <Uri>[];
      await openLinux(tester, opened, releasePage: page);
      await tester.tap(find.text('Ouvrir la page'));
      await tester.pumpAndSettle();
      expect(opened, [page]);
      expect(find.text('Version 0.1.1 disponible'), findsNothing);
      expect(find.textContaining('Téléchargement'), findsNothing);
    });

    testWidgets("« Plus tard » : rien d'ouvert ni de téléchargé", (
      tester,
    ) async {
      final opened = <Uri>[];
      await openLinux(tester, opened, releasePage: page);
      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.text('Version 0.1.1 disponible'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets("sans page sûre : pas de bouton pour l'ouvrir", (tester) async {
      await openLinux(tester, []);
      expect(find.text('Ouvrir la page'), findsNothing);
    });
  });
}
