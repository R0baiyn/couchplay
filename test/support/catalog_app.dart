import 'dart:convert';
import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/accounts/server_session.dart';
import 'package:couchplay/app.dart';
import 'package:couchplay/catalog/catalog_index.dart';
import 'package:couchplay/catalog/catalog_screen.dart';
import 'package:couchplay/home_shell.dart';
import 'package:couchplay/catalog/home_screen.dart';

import 'package:couchplay/server/models.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:couchplay/update/updater.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';
import 'settle.dart';

String fixture(String name) =>
    File('test/fixtures/$name.json').readAsStringSync();

// Le dossier du compte et le faux serveur de chaque test du catalogue.
late Directory root;
late HttpClientAdapter server;

void setUpCatalogApp() {
  setUp(() {
    root = Directory.systemTemp.createTempSync('couchplay_catalog_');
    server = FakeAdapter.routes({
      '': activeAccountJson,
      'get_vod_categories': fixture('vod_categories'),
      'get_vod_streams': fixture('vod_streams'),
      'get_vod_info': fixture('vod_info'),
      'get_series_categories': fixture('series_categories'),
      'get_series': fixture('series'),
      'get_series_info': fixture('series_info'),
    });
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Une écriture de l'app encore en cours garde un fichier ouvert (sous
      // Windows) : le dossier temporaire reste, sans effet sur les tests.
    }
  });
}

Future<void> pumpApp(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  bool openMovies = true,
  bool waitForIndex = true,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  // Comme au lancement de l'app : le dossier du compte existe.
  Directory('${root.path}/accounts/compte').createSync(recursive: true);
  FlutterSecureStorage.setMockInitialValues({});
  final store = await tester.runAsync(() async {
    final store = await AccountStore.open();
    await store.save(
      const AccountsState().withAccount(
        const Account(
          id: 'compte',
          name: 'Salon',
          host: 'http://example.com',
          username: 'u',
          password: 'p',
          userAgent: defaultUserAgent,
        ),
      ),
    );
    return store;
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appVersionProvider.overrideWithValue('0.1.0'),
        accountStoreProvider.overrideWithValue(store!),
        accountFilesProvider.overrideWithValue(
          AccountFiles(Directory('${root.path}/accounts')),
        ),
        serverClientFactoryProvider.overrideWithValue(
          (a) => ServerClient(
            host: a.host,
            username: a.username,
            password: a.password,
            userAgent: a.userAgent,
            adapter: server,
          ),
        ),
        ...overrides,
      ],
      child: const CouchPlayApp(home: HomeGate()),
    ),
  );
  await settle(tester);
  // Les index des films et des séries se chargent en arrière-plan, sans
  // roue visible : attendus ici, pour qu'aucune requête ne reste en vol à
  // la fin du test.
  final container = ProviderScope.containerOf(
    tester.element(find.byType(HomeShell)),
  );
  bool loading() => ContentKind.values.any(
    (kind) => container.read(catalogIndexProvider(kind)).isLoading,
  );
  for (var i = 0; waitForIndex && loading(); i++) {
    if (i == 100) fail('le catalogue ne se charge pas');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  // L'app s'ouvre sur l'accueil.
  if (openMovies) {
    await tester.tap(find.byKey(const ValueKey('shell.tabMovies')));
    await settle(tester);
  }
}

/// Progression enregistrée dans `library.json`, relue jusqu'à ce que
/// [done] la valide. L'app écrit en fond : chaque `pump` fait avancer
/// l'écriture, et une lecture pendant le renommage du fichier temporaire
/// (refusée sous Windows) est simplement refaite.
Future<Map<Object?, Object?>> savedProgress(
  WidgetTester tester,
  bool Function(Map<Object?, Object?> progress) done,
) async {
  final file = File('${root.path}/accounts/compte/library.json');
  var progress = <Object?, Object?>{};
  for (var i = 0; i < 100 && !done(progress); i++) {
    await tester.pump(const Duration(milliseconds: 20));
    progress =
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          try {
            final saved = jsonDecode(await file.readAsString()) as Map;
            return saved['progress'] as Map<Object?, Object?>;
          } on FileSystemException {
            return progress;
          }
        }) ??
        progress;
  }
  return progress;
}

/// Un texte dans la rangée « Continuer à regarder » (la première rangée) :
/// l'historique et « Vus » répètent les mêmes titres plus bas.
Finder inContinue(String text) => find.descendant(
  of: find
      .descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(SingleChildScrollView),
      )
      .first,
  matching: find.text(text),
);

/// Liste des catégories du grand écran : défile jusqu'à la catégorie [id],
/// l'ouvre.
Future<void> openCategory(WidgetTester tester, String id) async {
  final tile = find.byKey(ValueKey('catalog.categoryTile.$id'));
  await tester.scrollUntilVisible(
    tile,
    200,
    // Pas celui du rail.
    scrollable: find
        .descendant(
          of: find.byType(CatalogScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(tile);
  await settle(tester);
}
