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
  _FakeInstaller(
    this.workDir, {
    this.fails = false,
    this.signed = false,
    this.free,
  });

  /// Réponse de [freeSpace] : `null`, place inconnue.
  final int? free;

  @override
  final Directory workDir;

  /// [installNow] lève l'erreur d'Android sans installateur.
  final bool fails;

  var installs = 0;
  var prepares = 0;

  @override
  String get assetSuffix => '-android-arm64.apk';

  @override
  Future<void> Function(Uri page)? get openPage => null;

  @override
  final bool signed;

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
  Future<bool> installPending(
    String current, {
    Future<bool> Function(int size)? allow,
  }) async => false;

  @override
  Future<int?> freeSpace() async => free;
}

/// Message de tout échec de la mise à jour (Q-29).
const impossible = "Mise à jour impossible pour l'instant.";

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
    bool signed = false,
    int? free,
    FakeAdapter? adapter,
  }) async {
    final installer = _FakeInstaller(
      Directory('${work.path}${Platform.pathSeparator}update'),
      fails: fails,
      signed: signed,
      free: free,
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
              key: const ValueKey('test.open'),
              onPressed: () => showUpdateDialog(context, updater, update),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('test.open')));
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
    await tester.tap(find.byKey(const ValueKey('update.install')));
    await tester.pump();
    expect(find.text('Téléchargement : 0 %'), findsOneWidget);
    expect(find.byKey(const ValueKey('update.progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('update.cancel')), findsOneWidget);

    await waitFor(tester, () => installer.installs > 0);
    expect(installer.installs, 1);
    expect(find.textContaining('Téléchargement'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('« Mettre à jour » : un échec ferme la progression et le dit', (
    tester,
  ) async {
    final (_, installer) = await open(tester, fails: true);
    await tester.tap(find.byKey(const ValueKey('update.install')));
    await waitFor(tester, () => installer.installs > 0);
    expect(find.textContaining('Téléchargement'), findsNothing);
    expect(find.text(impossible), findsOneWidget);
  });

  testWidgets('« Mettre à jour » : signature refusée, rien installé, dit', (
    tester,
  ) async {
    // La liste de la release n'est pas signée : refus net.
    final (_, installer) = await open(tester, signed: true);
    await tester.tap(find.byKey(const ValueKey('update.install')));
    await waitFor(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
    expect(find.textContaining('Téléchargement'), findsNothing);
    expect(find.text(impossible), findsOneWidget);
    expect(installer.prepares, 0);
    expect(installer.installs, 0);
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
    await tester.tap(find.byKey(const ValueKey('update.install')));
    await waitFor(tester, () => updater.progress.value > 0);

    await tester.tap(find.byKey(const ValueKey('update.cancel')));
    await waitFor(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
    expect(find.textContaining('Téléchargement'), findsNothing);
    expect(find.text('Mise à jour annulée.'), findsOneWidget);
    expect(installer.installs, 0);
  });

  testWidgets('« Plus tard » : téléchargée une fois, puis le message', (
    tester,
  ) async {
    final (_, installer) = await open(tester);
    await tester.tap(find.byKey(const ValueKey('update.later')));
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

  testWidgets('« Plus tard » puis échec du téléchargement : dit', (
    tester,
  ) async {
    final (_, installer) = await open(
      tester,
      adapter: FakeAdapter.replying('', status: 404),
    );
    await tester.tap(find.byKey(const ValueKey('update.later')));
    await waitFor(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
    expect(find.text(impossible), findsOneWidget);
    expect(installer.prepares, 0);
  });

  testWidgets('« Plus tard » puis signature refusée : dit', (tester) async {
    final (_, installer) = await open(tester, signed: true);
    await tester.tap(find.byKey(const ValueKey('update.later')));
    await waitFor(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
    expect(find.text(impossible), findsOneWidget);
    expect(installer.prepares, 0);
  });

  group('place insuffisante', () {
    // Moins que 3 APK de 3 octets + 500 Mio de réserve (D-057).
    const low = 1000;

    for (final (button, label) in [
      ('update.install', 'Mettre à jour'),
      ('update.later', 'Plus tard'),
    ]) {
      testWidgets('« $label » : avertit, « Continuer quand même » télécharge', (
        tester,
      ) async {
        final adapter = FakeAdapter.replying('abc');
        final (_, installer) = await open(tester, free: low, adapter: adapter);
        await tester.tap(find.byKey(ValueKey(button)));
        await tester.pumpAndSettle();
        expect(find.text('Place insuffisante'), findsOneWidget);
        expect(find.textContaining('1 Ko libres'), findsOneWidget);
        expect(adapter.calls, 0, reason: 'rien avant le choix');

        await tester.tap(find.byKey(const ValueKey('update.spaceContinue')));
        await waitFor(tester, () => installer.prepares > 0);
        expect(find.text('Place insuffisante'), findsNothing);
        expect(installer.installs, button == 'update.install' ? 1 : 0);
      });

      testWidgets('« $label » puis « Annuler » : rien téléchargé ni dit', (
        tester,
      ) async {
        final adapter = FakeAdapter.replying('abc');
        final (_, installer) = await open(tester, free: low, adapter: adapter);
        await tester.tap(find.byKey(ValueKey(button)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('update.spaceCancel')));
        await tester.pumpAndSettle();
        expect(find.text('Place insuffisante'), findsNothing);
        expect(find.textContaining('Téléchargement'), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(adapter.calls, 0);
        expect(installer.prepares, 0);
        expect(installer.installs, 0);
      });
    }

    testWidgets('place suffisante : aucune boîte, téléchargé', (tester) async {
      final (_, installer) = await open(tester, free: 10000000000);
      await tester.tap(find.byKey(const ValueKey('update.install')));
      await tester.pump();
      expect(find.text('Place insuffisante'), findsNothing);
      await waitFor(tester, () => installer.installs > 0);
      expect(find.text('Place insuffisante'), findsNothing);
    });

    /// Au démarrage : la boîte d'une mise à jour en attente, ouverte.
    Future<_FakeInstaller> openHeld(WidgetTester tester) async {
      final installer = _FakeInstaller(work);
      final updater = Updater(version: '0.1.0', installer: installer);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('test.open'),
                onPressed: () => showHeldUpdateDialog(
                  context,
                  updater,
                  const ShortOfSpace(free: 572723200, needed: 583188918),
                ),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('test.open')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('573 Mo libres, environ 583 Mo'),
        findsOneWidget,
      );
      return installer;
    }

    testWidgets('au démarrage, « Continuer quand même » installe', (
      tester,
    ) async {
      final installer = await openHeld(tester);
      expect(installer.installs, 0);
      await tester.tap(find.byKey(const ValueKey('update.spaceContinue')));
      await tester.pumpAndSettle();
      expect(installer.installs, 1);
    });

    testWidgets('au démarrage, « Annuler » n\'installe rien', (tester) async {
      final installer = await openHeld(tester);
      await tester.tap(find.byKey(const ValueKey('update.spaceCancel')));
      await tester.pumpAndSettle();
      expect(installer.installs, 0);
      expect(find.byType(SnackBar), findsNothing);
    });
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
                key: const ValueKey('test.open'),
                onPressed: () =>
                    showUpdateDialog(context, updater, linuxUpdate),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('test.open')));
      await tester.pumpAndSettle();
      expect(find.text('Version 0.1.1 disponible'), findsOneWidget);
      expect(find.text('Nouveautés'), findsOneWidget);
      expect(find.byKey(const ValueKey('update.notes')), findsOneWidget);
      expect(find.byKey(const ValueKey('update.install')), findsNothing);
    }

    testWidgets('« Ouvrir la page » : la release, sans téléchargement', (
      tester,
    ) async {
      final opened = <Uri>[];
      await openLinux(tester, opened, releasePage: page);
      await tester.tap(find.byKey(const ValueKey('update.openPage')));
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
      await tester.tap(find.byKey(const ValueKey('update.later')));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.text('Version 0.1.1 disponible'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets("sans page sûre : pas de bouton pour l'ouvrir", (tester) async {
      await openLinux(tester, []);
      expect(find.byKey(const ValueKey('update.openPage')), findsNothing);
    });
  });
}
