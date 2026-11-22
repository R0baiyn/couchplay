// Parcours 4 de Docs/FEATURES.md : mise à jour signée, jusqu'avant
// l'installation. La release, sa liste signée et le paquet sont servis par un
// faux adaptateur HTTP (aucune requête vers GitHub), signés par une clé de
// test ; l'installateur est factice et n'installe rien.
// Lancé par app_test.dart : flutter test integration_test -d windows.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:couchplay/update/release_signature.dart';
import 'package:couchplay/update/updater.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_server.dart';
import 'bench.dart';

/// Graines fixes des clés de test : la bonne (celle que l'app d'essai
/// connaît) et une autre. Jamais la clé des releases.
final _testSeed = List<int>.filled(keyLength, 7);
final _otherSeed = List<int>.filled(keyLength, 8);

const _version = '9.9.9';
const _notes = 'Notes de la version d’essai.';
const _assetName = 'couchplay-$_version-windows-setup.exe';
final _asset = Uri.https(
  'github.com',
  '/R0baiyn/couchplay/releases/download/v$_version/$_assetName',
);

/// Le paquet : 256 Kio quelconques, servis en deux moitiés.
final _package = Uint8List.fromList([
  for (var i = 0; i < 256 * 1024; i++) i % 251,
]);
final _packageSum = sha256.convert(_package).toString();

/// Installation simulée : retient les sommes du fichier reçu et compte les
/// installations demandées, sans rien lancer.
final class _FakeInstaller implements Installer {
  _FakeInstaller(this.workDir);

  @override
  final Directory workDir;

  final preparedSums = <String>[];
  var installs = 0;

  /// Versions reçues par [installPending], et installations qu'il a lancées.
  final pendingChecks = <String>[];
  var pendingInstalls = 0;

  @override
  String get assetSuffix => '-windows-setup.exe';

  @override
  Future<void> Function(Uri page)? get openPage => null;

  @override
  bool get signed => true;

  @override
  String get later => 'à la fermeture de l’app';

  @override
  String get packageName => 'update.exe';

  @override
  Future<void> prepared(Update update, File package, String? sha256) async =>
      // Somme du fichier reçu, puis celle transmise pour l'installation.
      preparedSums.add('${await sha256OfFile(package)} $sha256');

  @override
  Future<void> installNow() async => installs++;

  @override
  Future<bool> installPending(
    String current, {
    Future<bool> Function(int size)? allow,
  }) async {
    // Une mise à jour préparée lors d'une session précédente est en attente.
    pendingChecks.add(current);
    if (preparedSums.isEmpty) return false;
    pendingInstalls++;
    return true;
  }

  @override
  Future<int?> freeSpace() async => null;
}

/// La fausse release : `releases/latest`, puis la liste, sa signature par
/// [signer] et le paquet, dont la 2e moitié attend [rest] ; [served] est
/// complété une fois le paquet servi en entier. Chaque demande de
/// `releases/latest` est notée dans [checks] ; toute autre adresse est notée
/// dans [unexpected] et reçoit un 404.
Future<FakeAdapter> _release({
  required List<int> signer,
  required Future<void> rest,
  required Completer<void> served,
  required List<Uri> checks,
  required List<Uri> unexpected,
}) async {
  final sums = formatSums({
    _assetName: _packageSum,
    'couchplay-$_version-windows-portable.zip': '0' * 64,
  });
  final signature = await signBytes(utf8.encode(sums), signer);
  final latest = jsonEncode({
    'tag_name': 'v$_version',
    'body': _notes,
    'html_url': 'https://github.com/R0baiyn/couchplay/releases/tag/v$_version',
    'assets': [
      {
        'name': _assetName,
        'browser_download_url': '$_asset',
        'size': _package.length,
      },
    ],
  });
  Stream<Uint8List> package() async* {
    final half = _package.length ~/ 2;
    yield _package.sublist(0, half);
    await rest;
    yield _package.sublist(half);
    served.complete();
  }

  return FakeAdapter((options) async {
    final url = options.uri;
    if (url.host == Updater.latest.host && url.path == Updater.latest.path) {
      checks.add(url);
      return ResponseBody.fromString(
        latest,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    // Même dossier que le paquet : seule la fin du chemin change.
    final sibling =
        isAllowedDownload(url) && url.resolve('.') == _asset.resolve('.');
    return switch (sibling ? url.pathSegments.last : null) {
      sumsName => ResponseBody.fromString(sums, 200),
      signatureName => ResponseBody.fromString(signature, 200),
      _assetName => ResponseBody(package(), 200),
      _ => () {
        unexpected.add(url);
        return ResponseBody.fromString('', 404);
      }(),
    };
  });
}

/// Valeur de la barre de progression affichée.
double? _progress(WidgetTester tester) =>
    tester.widget<LinearProgressIndicator>(byKey('update.progress')).value;

/// Une app lancée sur la fausse release : la fin du paquet attend [rest],
/// [served] dit qu'il est servi en entier ; [checks] et [unexpected] : voir
/// [_release].
typedef _Started = ({
  IsolatedApp app,
  _FakeInstaller installer,
  Completer<void> rest,
  Completer<void> served,
  List<Uri> checks,
  List<Uri> unexpected,
});

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Nul si le démarrage a échoué : son erreur reste la seule affichée.
  FakeServer? server;
  setUpAll(() async => server = await FakeServer.start());
  tearDownAll(() async => server?.stop());

  /// Démarre l'app, version [installed], avec une release signée par
  /// [signer], puis ajoute le compte. Sans [installer], un installateur
  /// factice neuf ; le même, pour un 2e démarrage dans le même test.
  Future<_Started> startWithRelease(
    WidgetTester tester, {
    List<int>? signer,
    String installed = benchVersion,
    _FakeInstaller? installer,
  }) async {
    if (installer == null) {
      final root = await Directory.systemTemp.createTemp('couchplay_maj_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      installer = _FakeInstaller(
        Directory('${root.path}${Platform.pathSeparator}update'),
      );
    }
    final rest = Completer<void>();
    // La fin du paquet ne reste jamais suspendue après le test.
    addTearDown(() {
      if (!rest.isCompleted) rest.complete();
    });
    final served = Completer<void>();
    final checks = <Uri>[];
    final unexpected = <Uri>[];
    final app = await startIsolatedApp(
      tester,
      updater: Updater(
        version: installed,
        installer: installer,
        publicKey: await publicKeyOf(_testSeed),
        adapter: await _release(
          signer: signer ?? _testSeed,
          rest: rest.future,
          served: served,
          checks: checks,
          unexpected: unexpected,
        ),
      ),
    );
    await addBenchAccount(tester, server!);
    return (
      app: app,
      installer: installer,
      rest: rest,
      served: served,
      checks: checks,
      unexpected: unexpected,
    );
  }

  /// 1. La boîte s'ouvre devant l'Accueil : version, notes, deux choix.
  Future<void> waitOffer(WidgetTester tester) async {
    await waitFor(tester, byKey('update.install'));
    expect(find.text('Version $_version disponible'), findsOneWidget);
    expect(tester.widget<Text>(byKey('update.notes')).data, _notes);
    expect(byKey('update.later'), findsOneWidget);
  }

  /// Démarre l'app avec une release signée par [signer], accepte la mise à
  /// jour et attend la moitié du téléchargement.
  Future<_Started> acceptUpdate(WidgetTester tester, List<int> signer) async {
    final started = await startWithRelease(tester, signer: signer);
    await waitOffer(tester);

    // 2. Accepter : la boîte « Mise à jour » montre l'avancement, à mi-course
    // tant que la fin du paquet n'est pas servie.
    await tester.tap(byKey('update.install'));
    await waitFor(tester, byKey('update.progress'));
    expect(byKey('update.cancel'), findsOneWidget);
    await waitUntil(
      tester,
      () => (_progress(tester) ?? 0) > 0,
      what: 'la barre de progression monte',
    );
    expect(_progress(tester), lessThan(1));
    expect(find.textContaining('Téléchargement : '), findsOneWidget);
    return started;
  }

  testWidgets('parcours 4 : mise à jour signée, jusqu’avant l’installation', (
    tester,
  ) async {
    final (:installer, :rest, :unexpected, app: _, served: _, checks: _) =
        await acceptUpdate(tester, _testSeed);

    // 3. Fin du paquet : vérifié puis confié une fois à l'installateur, avec
    // la somme de la release ; la boîte de progression se ferme.
    rest.complete();
    await waitUntil(
      tester,
      () => installer.installs > 0,
      what: 'l’installateur factice est appelé',
    );
    await waitUntil(
      tester,
      () => byKey('update.progress').evaluate().isEmpty,
      what: 'la boîte « Mise à jour » se ferme',
    );
    expect(installer.installs, 1);
    expect(installer.preparedSums, ['$_packageSum $_packageSum']);
    expect(find.text('Mise à jour impossible pour l\'instant.'), findsNothing);
    expect(unexpected, isEmpty, reason: 'requête hors de la release');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('parcours 4 : signature d’une autre clé refusée', (tester) async {
    final (:installer, :rest, :served, :unexpected, app: _, checks: _) =
        await acceptUpdate(tester, _otherSeed);

    // 4. Liste signée par une autre clé : refus dit à l'utilisateur, rien
    // confié à l'installateur, aucun fichier non vérifié ne reste.
    rest.complete();
    await waitFor(tester, find.text('Mise à jour impossible pour l\'instant.'));
    await waitUntil(
      tester,
      () => byKey('update.progress').evaluate().isEmpty,
      what: 'la boîte « Mise à jour » se ferme',
    );
    // Le message vaut pour tout échec : seul le paquet servi en entier
    // montre que le refus vient de la vérification, qui le suit.
    expect(served.isCompleted, isTrue, reason: 'paquet servi en entier');
    expect(installer.preparedSums, isEmpty);
    expect(installer.installs, 0);
    expect(installer.workDir.existsSync(), isFalse, reason: 'fichier effacé');
    expect(unexpected, isEmpty, reason: 'requête hors de la release');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('parcours 4 : « Plus tard », installée au démarrage suivant', (
    tester,
  ) async {
    final first = await startWithRelease(tester);
    final installer = first.installer;
    await waitOffer(tester);

    // 5. « Plus tard » : téléchargée et préparée en fond, sans installation ;
    // le message dit quand elle s'installera.
    await tester.tap(byKey('update.later'));
    first.rest.complete();
    await waitFor(
      tester,
      find.text(
        'Mise à jour prête : elle s\'installera à la fermeture de l’app.',
      ),
    );
    expect(byKey('update.progress'), findsNothing);
    expect(installer.preparedSums, ['$_packageSum $_packageSum']);
    expect(installer.installs, 0);
    expect(first.unexpected, isEmpty, reason: 'requête hors de la release');

    // Démarrage suivant, même installateur : la mise à jour en attente
    // s'installe d'abord, et rien n'est proposé (GitHub n'est pas consulté).
    await first.app.stop();
    final next = await startWithRelease(tester, installer: installer);
    final offer = await next.app.container.read(startupUpdateProvider.future);
    expect(offer, isNull);
    expect(installer.pendingChecks, [benchVersion, benchVersion]);
    expect(installer.pendingInstalls, 1);
    expect(next.checks, isEmpty, reason: 'mise à jour proposée');
    expect(byKey('update.install'), findsNothing);
    expect(installer.installs, 0);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('parcours 4 : téléchargement annulé', (tester) async {
    final (:installer, :served, :unexpected, app: _, rest: _, checks: _) =
        await acceptUpdate(tester, _testSeed);

    // 6. « Annuler » à mi-course : la boîte se ferme, le message le dit, rien
    // n'est confié à l'installateur ni laissé sur le disque.
    await tester.tap(byKey('update.cancel'));
    await waitFor(tester, find.text('Mise à jour annulée.'));
    await waitUntil(
      tester,
      () => byKey('update.progress').evaluate().isEmpty,
      what: 'la boîte « Mise à jour » se ferme',
    );
    expect(served.isCompleted, isFalse, reason: 'paquet servi en entier');
    expect(installer.preparedSums, isEmpty);
    expect(installer.installs, 0);
    expect(installer.workDir.existsSync(), isFalse, reason: 'fichier laissé');
    expect(unexpected, isEmpty, reason: 'requête hors de la release');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('parcours 4 : réglages, l’app est à jour', (tester) async {
    // L'app installée a la version de la release publiée : rien au
    // démarrage, et la recherche des Réglages le dit.
    final started = await startWithRelease(tester, installed: _version);
    final offer = await started.app.container.read(
      startupUpdateProvider.future,
    );
    expect(offer, isNull);
    expect(started.checks, hasLength(1), reason: 'GitHub consulté au début');

    // 7. Réglages → Version : « CouchPlay est à jour. », aucune boîte.
    await waitFor(tester, byKey('settings.open'));
    await tester.tap(byKey('settings.open'));
    await waitFor(tester, byKey('settings.version'));
    await tester.ensureVisible(byKey('settings.version'));
    await tester.tap(byKey('settings.version'));
    await waitFor(tester, find.text('CouchPlay est à jour.'));
    expect(started.checks, hasLength(2), reason: 'GitHub consulté de nouveau');
    expect(byKey('update.install'), findsNothing);
    expect(started.installer.preparedSums, isEmpty);
    expect(started.unexpected, isEmpty, reason: 'requête hors de la release');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
