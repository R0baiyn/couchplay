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

/// Installation simulée : retient la somme du fichier reçu et compte les
/// installations demandées, sans rien lancer.
final class _FakeInstaller implements Installer {
  _FakeInstaller(this.workDir);

  @override
  final Directory workDir;

  final preparedSums = <String>[];
  var installs = 0;

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
  Future<void> prepared(Update update, File package) async =>
      preparedSums.add(await sha256OfFile(package));

  @override
  Future<void> installNow() async => installs++;

  @override
  Future<bool> installPending(String current) async => false;
}

/// La fausse release : `releases/latest`, puis la liste, sa signature par
/// [signer] et le paquet, dont la 2e moitié attend [rest] ; [served] est
/// complété une fois le paquet servi en entier. Toute autre adresse est
/// notée dans [unexpected] et reçoit un 404.
Future<FakeAdapter> _release({
  required List<int> signer,
  required Future<void> rest,
  required Completer<void> served,
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Nul si le démarrage a échoué : son erreur reste la seule affichée.
  FakeServer? server;
  setUpAll(() async => server = await FakeServer.start());
  tearDownAll(() async => server?.stop());

  /// Démarre l'app avec une release signée par [signer], ajoute le compte,
  /// accepte la mise à jour et attend la moitié du téléchargement.
  /// Rend l'installateur factice, ce qui libère la fin du paquet, ce qui dit
  /// qu'il est servi en entier, et les adresses hors de la release.
  Future<(_FakeInstaller, Completer<void>, Completer<void>, List<Uri>)>
  acceptUpdate(WidgetTester tester, List<int> signer) async {
    final root = await Directory.systemTemp.createTemp('couchplay_maj_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final installer = _FakeInstaller(
      Directory('${root.path}${Platform.pathSeparator}update'),
    );
    final rest = Completer<void>();
    // La fin du paquet ne reste jamais suspendue après le test.
    addTearDown(() {
      if (!rest.isCompleted) rest.complete();
    });
    final served = Completer<void>();
    final unexpected = <Uri>[];
    await startIsolatedApp(
      tester,
      updater: Updater(
        version: benchVersion,
        installer: installer,
        publicKey: await publicKeyOf(_testSeed),
        adapter: await _release(
          signer: signer,
          rest: rest.future,
          served: served,
          unexpected: unexpected,
        ),
      ),
    );
    await addBenchAccount(tester, server!);

    // 1. La boîte s'ouvre devant l'Accueil : version, notes, deux choix.
    await waitFor(tester, byKey('update.install'));
    expect(find.text('Version $_version disponible'), findsOneWidget);
    expect(tester.widget<Text>(byKey('update.notes')).data, _notes);
    expect(byKey('update.later'), findsOneWidget);

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
    return (installer, rest, served, unexpected);
  }

  testWidgets('parcours 4 : mise à jour signée, jusqu’avant l’installation', (
    tester,
  ) async {
    final (installer, rest, _, unexpected) = await acceptUpdate(
      tester,
      _testSeed,
    );

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
    expect(installer.preparedSums, [_packageSum]);
    expect(find.text('Mise à jour impossible pour l\'instant.'), findsNothing);
    expect(unexpected, isEmpty, reason: 'requête hors de la release');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('parcours 4 : signature d’une autre clé refusée', (tester) async {
    final (installer, rest, served, unexpected) = await acceptUpdate(
      tester,
      _otherSeed,
    );

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
}
