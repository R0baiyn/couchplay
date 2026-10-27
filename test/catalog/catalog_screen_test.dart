import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/accounts/server_session.dart';
import 'package:couchplay/app.dart';
import 'package:couchplay/catalog/movie_screen.dart';
import 'package:couchplay/catalog/poster_grid.dart';
import 'package:couchplay/catalog/series_screen.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:couchplay/settings/settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../support/fake_server.dart';

String _fixture(String name) =>
    File('test/fixtures/$name.json').readAsStringSync();

void main() {
  late Directory root;
  late HttpClientAdapter server;

  setUp(() {
    root = Directory.systemTemp.createTempSync('couchplay_catalog_');
    server = FakeAdapter.routes({
      '': activeAccountJson,
      'get_vod_categories': _fixture('vod_categories'),
      'get_vod_streams': _fixture('vod_streams'),
      'get_vod_info': _fixture('vod_info'),
      'get_series_categories': _fixture('series_categories'),
      'get_series': _fixture('series'),
      'get_series_info': _fixture('series_info'),
    });
  });
  tearDown(() => root.deleteSync(recursive: true));

  // Réseau factice, disque et isolates réels : quelques tours de vraie
  // horloge, sans pumpAndSettle (les roues de chargement tournent sans fin).
  Future<void> settle(WidgetTester tester) async {
    // Le premier isolate d'un test démarre lentement : on attend la fin des
    // chargements (plus de roue), au plus quelques secondes.
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final loading = find.byType(CircularProgressIndicator).evaluate();
      // Fini : plus de chargement ni d'animation (transition de page).
      if (i > 2 && loading.isEmpty && !tester.binding.hasScheduledFrame) {
        return;
      }
    }
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final settings = await tester.runAsync(SettingsStore.open);
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
          settingsStoreProvider.overrideWithValue(settings!),
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
        ],
        child: const CouchPlayApp(home: HomeGate()),
      ),
    );
    await settle(tester);
  }

  testWidgets('Films : catégories françaises, grille, puis fiche', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('FR · Drame'), findsOneWidget);
    expect(find.text('Films 4K'), findsOneWidget);
    expect(find.text('AR · ARABE أفلام عربية'), findsNothing);
    expect(find.text('VOST · Films'), findsNothing);
    // Grille de la première catégorie (le faux serveur renvoie la fixture).
    expect(find.text('Libre (2024) HD VF'), findsOneWidget);

    await tester.tap(find.text('Libre (2024) HD VF'));
    await settle(tester);

    expect(find.byType(MovieScreen), findsOneWidget);
    expect(find.textContaining('Mélanie Laurent'), findsOneWidget);
    expect(find.text('2024  ·  1 h 50  ·  ★ 6.6'), findsOneWidget);

    // Échap ramène à la grille.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(MovieScreen), findsNothing);
    expect(find.text('Libre (2024) HD VF'), findsOneWidget);
  });

  testWidgets('Séries : catégories, fiche, saisons et épisodes', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Séries'));
    await settle(tester);

    expect(find.text('Séries NETFLIX'), findsOneWidget);
    expect(find.text('Séries SUB-AR'), findsNothing);

    await tester.tap(find.text('Vikings'));
    await settle(tester);

    expect(find.byType(SeriesScreen), findsOneWidget);
    expect(find.text('Saison 1'), findsOneWidget);
    expect(find.text('Saison 2'), findsOneWidget);
    final firstEpisode = find.textContaining('1. Vikings - S01E01');
    await tester.scrollUntilVisible(firstEpisode, 300);
    expect(firstEpisode, findsOneWidget);

    await tester.scrollUntilVisible(find.text('Saison 2'), -300);
    await tester.tap(find.text('Saison 2'));
    await tester.pump();
    expect(firstEpisode, findsNothing);
    await tester.scrollUntilVisible(find.textContaining('S02E01'), 300);
    expect(find.textContaining('S02E01'), findsOneWidget);
  });

  testWidgets('écran étroit : catégories dans un menu, onglets en bas', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(400, 800));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(DropdownMenu<String>), findsOneWidget);
    expect(find.text('Libre (2024) HD VF'), findsOneWidget);
  });

  testWidgets('hors ligne avec un cache : bandeau ; sans cache : Réessayer', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.textContaining('Hors ligne'), findsNothing);

    // Nouveau lancement, serveur injoignable, cache d'il y a 25 h.
    server = FakeAdapter.failing(DioExceptionType.connectionError);
    final old = DateTime.now().subtract(const Duration(hours: 25));
    await tester.runAsync(() async {
      await for (final file in root.list(recursive: true)) {
        if (file is File) await file.setLastModified(old);
      }
    });
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester);

    expect(find.textContaining('Hors ligne'), findsOneWidget);
    expect(find.text('Libre (2024) HD VF'), findsOneWidget);

    // Plus de cache du tout : message et bouton.
    await tester.runAsync(() => root.delete(recursive: true));
    root.createSync();
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester);
    expect(find.text('Serveur injoignable'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('la grille se parcourt aux flèches, Entrée ouvre la fiche', (
    tester,
  ) async {
    await pumpApp(tester);

    // Tab jusqu'à la première affiche (après les onglets et les catégories),
    // puis flèche droite : la seconde.
    bool onPoster() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<PosterTile>() !=
        null;
    for (var i = 0; i < 60 && !onPoster(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    expect(onPoster(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);

    expect(find.byType(MovieScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Libre (2024) FHD VF'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('cocher un pays dans les réglages l\'affiche aussitôt', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('AR · ARABE أفلام عربية'), findsNothing);

    await tester.tap(find.text('Réglages'));
    await settle(tester);
    await tester.tap(find.text('Catalogue'));
    await settle(tester);
    await tester.tap(find.text('Arabe'));
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await tester.tap(find.text('Films').first);
    await settle(tester);

    await tester.scrollUntilVisible(
      find.text('AR · ARABE أفلام عربية'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('AR · ARABE أفلام عربية'), findsOneWidget);
  });
}
