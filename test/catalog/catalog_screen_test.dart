import 'dart:convert';
import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/accounts/server_session.dart';
import 'package:couchplay/app.dart';
import 'package:couchplay/catalog/movie_screen.dart';
import 'package:couchplay/catalog/poster_grid.dart';
import 'package:couchplay/catalog/series_screen.dart';
import 'package:couchplay/library/favorites_screen.dart';
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
import '../support/settle.dart';

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

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    bool openMovies = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Comme au lancement de l'app : le dossier du compte existe.
    Directory('${root.path}/accounts/compte').createSync(recursive: true);
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
    // L'app s'ouvre sur l'accueil.
    if (openMovies) {
      await tester.tap(find.text('Films'));
      await settle(tester);
    }
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

  testWidgets("un favori ajouté sur une fiche apparaît sur l'accueil", (
    tester,
  ) async {
    await pumpApp(tester, openMovies: false);
    expect(find.textContaining('Ma liste est vide'), findsOneWidget);

    await tester.tap(find.text('Films'));
    await settle(tester);
    await tester.tap(find.text('Libre (2024) HD VF'));
    await settle(tester);
    await tester.tap(find.byTooltip('Ajouter à ma liste'));
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    // Retour sur l'accueil, sans redémarrer.
    await tester.tap(find.text('Accueil'));
    await settle(tester);
    expect(find.textContaining('Ma liste est vide'), findsNothing);
    expect(find.text('Libre (2024) HD VF'), findsOneWidget);

    // « Tout voir » : grille filtrable.
    await tester.tap(find.text('Tout voir'));
    await settle(tester);
    expect(find.byType(FavoritesScreen), findsOneWidget);
    expect(find.text('Libre (2024) HD VF'), findsOneWidget);
    await tester.tap(find.text('Séries'));
    await settle(tester);
    expect(find.text('Libre (2024) HD VF'), findsNothing);
    expect(find.text('Rien dans ma liste ici.'), findsOneWidget);
    await tester.tap(find.text('Films'));
    await settle(tester);
    expect(find.text('Libre (2024) HD VF'), findsOneWidget);

    // La fiche s'ouvre depuis la grille ; retirer le favori le fait
    // disparaître au retour.
    await tester.tap(find.text('Libre (2024) HD VF'));
    await settle(tester);
    expect(find.byType(MovieScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Retirer de ma liste'));
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Libre (2024) HD VF'), findsNothing);
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

  testWidgets('un film commencé propose de reprendre ou de recommencer', (
    tester,
  ) async {
    // 12:34 regardées sur 1 h 50, enregistrées lors d'une séance précédente.
    File('${root.path}/accounts/compte/library.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'progress': {
            'movie:144014': {
              'name': 'Libre (2024) HD VF',
              'extension': 'mp4',
              'position': 754,
              'duration': 6600,
              'updatedAt': '2026-01-01T00:00:00Z',
            },
          },
        }),
      );
    await pumpApp(tester);
    await tester.tap(find.text('Libre (2024) HD VF'));
    await settle(tester);
    await tester.tap(find.text('Lecture'));
    await settle(tester);

    expect(find.text('Reprendre à 12:34'), findsOneWidget);
    expect(find.text('Recommencer'), findsOneWidget);
    // Fermer sans choisir laisse sur la fiche.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Reprendre à 12:34'), findsNothing);
    expect(find.byType(MovieScreen), findsOneWidget);
  });

  testWidgets('un épisode se marque vu ou non vu, et le reste', (tester) async {
    Future<void> openVikings() async {
      await tester.tap(find.text('Séries'));
      await settle(tester);
      await tester.tap(find.text('Vikings'));
      await settle(tester);
    }

    final firstEpisode = find.textContaining('1. Vikings - S01E01');
    final menu = find.byTooltip("Plus d'options");
    final seen = find.byIcon(Icons.check_circle);

    await pumpApp(tester);
    await openVikings();
    await tester.scrollUntilVisible(firstEpisode, 300);
    expect(seen, findsNothing);
    await tester.tap(menu.first);
    await settle(tester);
    await tester.tap(find.text('Marquer comme vu'));
    await settle(tester);
    expect(seen, findsOneWidget);

    // Nouveau lancement : toujours vu, et on peut l'annuler.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester);
    await openVikings();
    await tester.scrollUntilVisible(firstEpisode, 300);
    expect(seen, findsOneWidget);
    await tester.tap(menu.first);
    await settle(tester);
    await tester.tap(find.text('Marquer comme non vu'));
    await settle(tester);
    expect(seen, findsNothing);
  });

  testWidgets('« Continuer à regarder » : une entrée par série, « Retirer »', (
    tester,
  ) async {
    Map<String, Object?> episode(int number, int position, String date) => {
      'seriesId': '1',
      'season': 1,
      'episode': number,
      'name': 'Vikings',
      'extension': 'mkv',
      'position': position,
      'duration': 2700,
      'updatedAt': date,
    };
    final file = File('${root.path}/accounts/compte/library.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'progress': {
            'movie:144014': {
              'name': 'Libre (2024) HD VF',
              'extension': 'mp4',
              'position': 754,
              'duration': 6600,
              'updatedAt': '2026-01-01T00:00:00Z',
            },
            'movie:144015': {
              'name': 'Libre (2024) FHD VF',
              'extension': 'mkv',
              'position': 6600,
              'duration': 6600,
              'watched': true,
              'updatedAt': '2026-01-04T00:00:00Z',
            },
            'episode:6912': episode(1, 600, '2026-01-02T00:00:00Z'),
            'episode:6913': episode(2, 100, '2026-01-03T00:00:00Z'),
          },
        }),
      );
    await pumpApp(tester, openMovies: false);

    expect(find.text('Continuer à regarder'), findsOneWidget);
    // L'épisode le plus récent de la série, puis le film ; rien de vu.
    expect(find.text('Vikings · S1E2'), findsOneWidget);
    expect(find.text('Vikings · S1E1'), findsNothing);
    expect(find.text('Libre (2024) HD VF'), findsOneWidget);
    expect(find.text('Libre (2024) FHD VF'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Vikings · S1E2')).dx,
      lessThan(tester.getTopLeft(find.text('Libre (2024) HD VF')).dx),
    );

    // Appui long, « Retirer » : l'entrée part, la progression reste.
    await tester.longPress(find.text('Libre (2024) HD VF'));
    await settle(tester);
    await tester.tap(find.text('Retirer'));
    await settle(tester);
    expect(find.text('Libre (2024) HD VF'), findsNothing);
    expect(find.text('Vikings · S1E2'), findsOneWidget);
    final saved = await tester.runAsync(file.readAsString);
    final movie = (jsonDecode(saved!) as Map)['progress']['movie:144014'];
    expect(movie['position'], 754);
    expect(movie['hidden'], isTrue);
  });

  testWidgets('écran étroit : catégorie en panneau, en-tête repliable', (
    tester,
  ) async {
    // Assez bas pour que la grille de test (8 affiches) défile sous l'en-tête.
    await pumpApp(tester, size: const Size(400, 600));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Libre (2024) HD VF'), findsOneWidget);

    // Le bouton montre la catégorie choisie et ouvre le panneau ; toucher à
    // côté le ferme sans rien changer.
    final picker = find.widgetWithText(OutlinedButton, 'Films 4K');
    expect(picker, findsOneWidget);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(picker, findsOneWidget);

    // Choisir dans le panneau change de catégorie.
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('FR · Drame'),
      ),
    );
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'FR · Drame'), findsOneWidget);

    // Descendre replie l'en-tête, remonter un peu le fait revenir.
    final refresh = find.byTooltip('Actualiser').hitTestable();
    expect(refresh, findsOneWidget);
    await tester.dragFrom(const Offset(200, 400), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(refresh, findsNothing);
    await tester.dragFrom(const Offset(200, 300), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(refresh, findsOneWidget);
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

    await tester.tap(find.byTooltip('Réglages'));
    await settle(tester);
    await tester.tap(find.text('Catalogue'));
    await settle(tester);
    await tester.tap(find.text('Arabe'));
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    // Les réglages sont une page : Échap revient au catalogue.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    await tester.scrollUntilVisible(
      find.text('AR · ARABE أفلام عربية'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('AR · ARABE أفلام عربية'), findsOneWidget);
  });

  testWidgets('« Actualiser » recharge catégories et grille sans les cacher', (
    tester,
  ) async {
    await pumpApp(tester);
    final fake = server as FakeAdapter;
    final before = fake.calls;

    await tester.tap(find.byTooltip('Actualiser'));
    await tester.pump();
    // Pendant le rechargement, la grille reste là.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Libre (2024) HD VF'), findsOneWidget);

    await settle(tester);
    expect(fake.calls, before + 2, reason: 'catégories et liste, une fois');
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Libre (2024) HD VF'), findsOneWidget);
  });
}
