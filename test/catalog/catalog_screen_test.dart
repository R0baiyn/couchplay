import 'dart:async';
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
import 'package:couchplay/library/library_store.dart';
import 'package:couchplay/search/search_index.dart';
import 'package:couchplay/search/search_screen.dart';

import 'package:couchplay/server/models.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:couchplay/settings/settings_screen.dart';
import 'package:couchplay/television.dart';
import 'package:couchplay/update/updater.dart';
import 'package:couchplay/update/windows_installer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

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
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Une écriture de l'app encore en cours garde un fichier ouvert (sous
      // Windows) : le dossier temporaire reste, sans effet sur les tests.
    }
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    bool openMovies = true,
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
    for (var i = 0; i < 100 && loading(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    // L'app s'ouvre sur l'accueil.
    if (openMovies) {
      await tester.tap(find.text('Films'));
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

  /// Liste des catégories du grand écran : défile jusqu'à [name], l'ouvre.
  Future<void> openCategory(WidgetTester tester, String name) async {
    await tester.scrollUntilVisible(
      find.text(name),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(name));
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
    // Grille de la première catégorie (le faux serveur renvoie la fixture),
    // les trois versions de « Libre » en une seule affiche.
    expect(find.text('Libre (2024)'), findsOneWidget);

    await tester.tap(find.text('Libre (2024)'));
    await settle(tester);

    expect(find.byType(MovieScreen), findsOneWidget);
    expect(find.textContaining('Mélanie Laurent'), findsOneWidget);
    expect(find.text('2024  ·  1 h 50  ·  ★ 6.6'), findsOneWidget);

    // Échap ramène à la grille.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(MovieScreen), findsNothing);
    expect(find.text('Libre (2024)'), findsOneWidget);
  });

  testWidgets("la mise à jour attend que l'accueil soit devant", (
    tester,
  ) async {
    final found = Completer<Update?>();
    await pumpApp(
      tester,
      overrides: [
        // Aucun bouton n'est touché : rien n'est téléchargé ni lancé.
        updaterProvider.overrideWithValue(
          Updater(
            version: '0.1.0',
            installer: WindowsInstaller(portable: false, appDir: root),
            adapter: FakeAdapter.failing(DioExceptionType.connectionError),
          ),
        ),
        startupUpdateProvider.overrideWith((ref) => found.future),
      ],
    );
    final offer = find.text('Version 0.1.1 disponible');
    await tester.tap(find.text('Libre (2024)'));
    await settle(tester);

    // Trouvée pendant qu'une fiche est ouverte : rien par-dessus.
    found.complete(
      Update(
        version: '0.1.1',
        notes: '',
        asset: Uri.parse('https://github.com/x.exe'),
        size: 1,
      ),
    );
    await settle(tester);
    expect(find.byType(MovieScreen), findsOneWidget);
    expect(offer, findsNothing);

    // De retour sur l'accueil : proposée, une seule fois.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(offer, findsOneWidget);
  });

  testWidgets("un favori ajouté sur une fiche apparaît sur l'accueil", (
    tester,
  ) async {
    await pumpApp(tester, openMovies: false);
    expect(find.textContaining('Ma liste est vide'), findsOneWidget);

    await tester.tap(find.text('Films'));
    await settle(tester);
    await tester.tap(find.text('Libre (2024)'));
    await settle(tester);
    await tester.tap(find.byTooltip('Ajouter à ma liste'));
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    // Retour sur l'accueil, sans redémarrer.
    await tester.tap(find.text('Accueil'));
    await settle(tester);
    expect(find.textContaining('Ma liste est vide'), findsNothing);
    expect(find.text('Libre (2024)'), findsOneWidget);

    // « Tout voir » : grille filtrable.
    await tester.tap(find.text('Tout voir'));
    await settle(tester);
    expect(find.byType(FavoritesScreen), findsOneWidget);
    expect(find.text('Libre (2024)'), findsOneWidget);
    // Le favori est la version proposée sur la fiche : la meilleure.
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    await tester.tap(find.text('Séries'));
    await settle(tester);
    expect(find.text('Libre (2024)'), findsNothing);
    expect(find.text('Rien dans ma liste ici.'), findsOneWidget);
    await tester.tap(find.text('Films'));
    await settle(tester);
    expect(find.text('Libre (2024)'), findsOneWidget);

    // La fiche s'ouvre depuis la grille ; retirer le favori le fait
    // disparaître au retour.
    await tester.tap(find.text('Libre (2024)'));
    await settle(tester);
    expect(find.byType(MovieScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChoiceChip, skipOffstage: true),
        matching: find.text('4K'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Retirer de ma liste'));
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Libre (2024)'), findsNothing);
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
    // La fiche propose la version déjà commencée, pas la meilleure.
    await tester.tap(find.text('Libre (2024)'));
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

    // Nouveau lancement, une fois l'écriture faite : toujours vu, et on peut
    // l'annuler.
    bool watched(Map<Object?, Object?> progress) =>
        progress.values.any((e) => (e as Map)['watched'] == true);
    expect(watched(await savedProgress(tester, watched)), isTrue);
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
    final progress = await savedProgress(
      tester,
      (progress) => (progress['movie:144014'] as Map?)?['hidden'] == true,
    );
    final movie = progress['movie:144014'] as Map?;
    expect(movie?['position'], 754);
    expect(movie?['hidden'], isTrue);
  });

  testWidgets('épisode fini : « Continuer » propose le suivant', (
    tester,
  ) async {
    File('${root.path}/accounts/compte/library.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'progress': {
            'episode:6913': {
              'seriesId': '1',
              'season': 1,
              'episode': 2,
              'name': 'Vikings',
              'extension': 'mkv',
              'position': 2700,
              'duration': 2700,
              'watched': true,
              'updatedAt': '2026-01-03T00:00:00Z',
            },
          },
        }),
      );
    await pumpApp(tester, openMovies: false);
    // La tuile arrive avec la fiche de la série, sans roue de chargement.
    final next = find.text('Vikings · S1E3');
    for (var i = 0; i < 20 && next.evaluate().isEmpty; i++) {
      await settle(tester);
    }

    expect(find.text('Continuer à regarder'), findsOneWidget);
    expect(next, findsOneWidget);
    expect(find.text('Vikings · S1E2'), findsNothing);
  });

  testWidgets('écran étroit : catégorie en panneau, en-tête repliable', (
    tester,
  ) async {
    // Assez de films dans « FR · Drame » pour que sa grille défile sous
    // l'en-tête, sur un écran bas.
    final routes = server;
    final films = jsonDecode(_fixture('vod_streams')) as List<Object?>
      ..addAll([
        for (var i = 0; i < 30; i++)
          {
            'stream_id': 5000 + i,
            'name': 'Drame $i (${1990 + i})',
            'category_id': '118',
            'container_extension': 'mkv',
          },
      ]);
    server = FakeAdapter((options) async {
      if (options.uri.queryParameters['action'] == 'get_vod_streams') {
        return ResponseBody.fromString(jsonEncode(films), 200);
      }
      return routes.fetch(options, null, null);
    });
    await pumpApp(tester, size: const Size(400, 600));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Libre (2024)'), findsOneWidget);

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
    expect(find.text('Libre (2024)'), findsOneWidget);

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
    // Une catégorie de deux films : Libre, puis The King Tide.
    await openCategory(tester, 'FR · FILMS HD');

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
        matching: find.text('The King Tide (2024)'),
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
    expect(find.text('Libre (2024)'), findsOneWidget);

    await settle(tester);
    expect(
      fake.calls,
      before + 2,
      reason: 'catégories et liste complète, une fois chacune',
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Libre (2024)'), findsOneWidget);
  });

  testWidgets('tirer la grille vers le bas l\'actualise (toucher)', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(400, 800));
    final fake = server as FakeAdapter;
    final before = fake.calls;

    await tester.fling(find.text('Libre (2024)'), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(
      fake.calls,
      before + 2,
      reason: 'catégories et liste complète, une fois chacune',
    );
    expect(find.text('Libre (2024)'), findsOneWidget);
  });

  testWidgets('télécommande : au lancement, une flèche donne le focus', (
    tester,
  ) async {
    await pumpApp(tester, openMovies: false);
    // Rien n'a le focus tant qu'on n'a pas appuyé (pas de toucher sur TV).
    final primary = FocusManager.instance.primaryFocus;
    expect(primary is FocusScopeNode || primary == null, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus;
    expect(focused, isNot(isA<FocusScopeNode>()));
    expect(focused?.context, isNotNull);
  });

  testWidgets(
    'TV : la recherche se tape dans une fenêtre, sans clavier au passage',
    (tester) async {
      await pumpApp(
        tester,
        openMovies: false,
        overrides: [televisionProvider.overrideWithValue(true)],
      );
      await tester.tap(find.text('Recherche'));
      await settle(tester);
      expect(find.byType(EditableText), findsNothing);

      // La case de recherche a le focus ; OK ouvre la saisie.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'libre');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(find.text('Libre (2024)'), findsOneWidget);
    },
  );

  group('TV, à la télécommande', () {
    /// Une grille de 40 films dans « Films 4K », et l'app à la taille d'une
    /// TV (960 × 540).
    Future<void> pumpTv(WidgetTester tester) async {
      final film = (jsonDecode(_fixture('vod_streams')) as List).first as Map;
      server = FakeAdapter.routes({
        '': activeAccountJson,
        'get_vod_categories': _fixture('vod_categories'),
        'get_vod_streams': jsonEncode([
          for (var i = 0; i < 40; i++)
            {
              ...film,
              'stream_id': 1000 + i,
              'tmdb_id': 5000 + i,
              'category_id': '619',
              'name': 'Film $i (2020)',
            },
        ]),
        'get_vod_info': _fixture('vod_info'),
        'get_series_categories': _fixture('series_categories'),
        'get_series': _fixture('series'),
        'get_series_info': _fixture('series_info'),
      });
      await pumpApp(
        tester,
        size: const Size(960, 540),
        openMovies: false,
        overrides: [televisionProvider.overrideWithValue(true)],
      );
    }

    /// Le premier texte sous l'élément qui a le focus.
    String? focused() {
      String? text;
      void visit(Element element) {
        if (text != null) return;
        if (element.widget case Text(:final data)) text = data;
        element.visitChildElements(visit);
      }

      final context = FocusManager.instance.primaryFocus?.context;
      (context as Element?)?.visitChildElements(visit);
      return text;
    }

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await settle(tester);
    }

    testWidgets('rail et onglet : deux zones, chacune garde sa place', (
      tester,
    ) async {
      await pumpTv(tester);
      expect(focused(), 'Accueil', reason: 'le focus se voit au lancement');

      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      expect(focused(), 'Films');
      // Première entrée : la première affiche, pas « Actualiser ».
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), 'Film 0 (2020)');
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowDown);
      final visited = focused();
      expect(visited, isNot('Film 1 (2020)'), reason: 'une rangée plus bas');

      // ← au bord gauche : l'onglet choisi, pas l'élément le plus proche.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focused(), 'Films');
      // Le bas du rail le garde : pas de saut dans la grille.
      for (var i = 0; i < 5; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(find.byType(MovieScreen), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<SettingsButton>(),
        isNotNull,
        reason: 'le bouton des réglages, en bas du rail',
      );
      // → revient à la dernière affiche visitée.
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), isNot(anyOf('Films', 'Recherche', 'Réglages')));
      expect(focused(), startsWith('Film '));
    });

    testWidgets('fiche : ↓ sans rien dessous fait défiler la page', (
      tester,
    ) async {
      await pumpTv(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(MovieScreen), findsOneWidget);
      expect(focused(), 'Lecture');

      final before = tester.getTopLeft(find.text('Lecture')).dy;
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'Lecture', reason: 'le focus reste sur le bouton');
      expect(tester.getTopLeft(find.text('Lecture')).dy, lessThan(before));
    });
  });

  testWidgets('retour : d\'un onglet vers l\'Accueil, puis quitte', (
    tester,
  ) async {
    await pumpApp(tester);
    // Bouton retour d'Android : le même chemin que le système.
    Future<bool> back() async {
      final handled = await tester.binding.handlePopRoute();
      await settle(tester);
      return handled;
    }

    NavigationRail rail() => tester.widget(find.byType(NavigationRail));
    expect(rail().selectedIndex, 1);

    // Une fiche se ferme d'abord.
    await tester.tap(find.text('Libre (2024)'));
    await settle(tester);
    expect(find.byType(MovieScreen), findsOneWidget);
    expect(await back(), isTrue);
    expect(find.byType(MovieScreen), findsNothing);
    expect(rail().selectedIndex, 1);

    // Puis l'onglet Films ramène à l'Accueil, sans quitter.
    expect(await back(), isTrue);
    expect(rail().selectedIndex, 0);

    // À l'Accueil, retour quitte l'app (le système reprend la main).
    expect(await back(), isFalse);
  });

  testWidgets('Recherche : films et séries, accents, rien trouvé, Ctrl+F', (
    tester,
  ) async {
    await pumpApp(tester, openMovies: false);

    // Ctrl+F depuis l'accueil ouvre la recherche, le curseur dans le champ.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(find.byType(SearchScreen), findsOneWidget);
    final field = find.descendant(
      of: find.byType(SearchScreen),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);

    Future<void> type(String text) async {
      await tester.enterText(field, text);
      // La recherche part 300 ms après la dernière frappe.
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
    }

    await type('EGYPTE');
    expect(find.text('Films (1)'), findsOneWidget);
    expect(find.text('Le Prince d\'Égypte (1998)'), findsOneWidget);
    expect(find.textContaining('Séries ('), findsNothing);

    await type('vik');
    expect(find.text('Séries (1)'), findsOneWidget);
    expect(find.text('Vikings'), findsOneWidget);

    // Une seule affiche pour les trois versions.
    await type('libre');
    expect(find.text('Films (1)'), findsOneWidget);
    expect(find.text('Libre (2024)'), findsOneWidget);

    await type('zzz');
    expect(find.text('Aucun résultat pour « zzz ».'), findsOneWidget);
  });

  testWidgets('Fiche : versions, la meilleure d\'abord, favori de la choisie', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Libre (2024)'));
    await settle(tester);

    ChoiceChip chip(String label) =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
    expect(chip('4K').selected, isTrue);
    expect(chip('FHD VF').selected, isFalse);
    expect(chip('HD VF').selected, isFalse);

    await tester.tap(find.widgetWithText(ChoiceChip, 'HD VF'));
    await settle(tester);
    expect(chip('HD VF').selected, isTrue);
    expect(chip('4K').selected, isFalse);

    await tester.tap(find.byTooltip('Ajouter à ma liste'));
    await settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MovieScreen)),
    );
    expect(container.read(libraryProvider).favorites.keys, ['movie:144014']);
  });

  testWidgets('« / » : la recherche depuis les films ; rien sur une fiche', (
    tester,
  ) async {
    await pumpApp(tester);
    // Pas de champ dans les films : chercher passe par l'onglet Recherche.
    expect(find.byType(EditableText), findsNothing);

    // Sur une fiche, Ctrl+F et « / » ne font rien.
    await tester.tap(find.text('Libre (2024)'));
    await settle(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await settle(tester);
    expect(find.byType(MovieScreen), findsOneWidget);
    expect(find.byType(SearchScreen), findsNothing);

    // Revenu aux films, « / » ouvre la recherche, le curseur dans son champ.
    await tester.pageBack();
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await settle(tester);
    expect(find.byType(SearchScreen), findsOneWidget);
    final field = find.descendant(
      of: find.byType(SearchScreen),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    expect(tester.widget<EditableText>(field).controller.text, isEmpty);
  });

  testWidgets('pastilles : cœur et coche, même d\'une autre catégorie', (
    tester,
  ) async {
    // Vue : la version HD VF, rangée dans « FR · FILMS HD ». La grille de
    // « Films 4K » n'a que la 4K, mais marque quand même le film.
    File('${root.path}/accounts/compte/library.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'progress': {
            'movie:144014': {
              'name': 'Libre (2024) HD VF',
              'extension': 'mp4',
              'position': 5000,
              'duration': 5000,
              'watched': true,
              'updatedAt': '2026-01-01T00:00:00Z',
            },
          },
        }),
      );
    await pumpApp(tester);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);

    // La fiche propose la HD VF, déjà vue : c'est elle qui va dans la liste.
    await tester.tap(find.text('Libre (2024)'));
    await settle(tester);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'HD VF'))
          .selected,
      isTrue,
    );
    await tester.tap(find.byTooltip('Ajouter à ma liste'));

    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('une version introuvable laisse choisir les autres', (
    tester,
  ) async {
    // La 4K, proposée d'office, a disparu du serveur.
    final routes = server;
    server = FakeAdapter((options) async {
      if (options.uri.queryParameters['vod_id'] == '144016') {
        return ResponseBody.fromString('', 500);
      }
      return routes.fetch(options, null, null);
    });
    await pumpApp(tester);
    await tester.tap(find.text('Libre (2024)'));
    await settle(tester);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.text('Lecture'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'HD VF'));
    await settle(tester);
    expect(find.text('Réessayer'), findsNothing);
    expect(find.text('Lecture'), findsOneWidget);
  });

  testWidgets('« Actualiser » : un film ajouté au serveur se trouve aussitôt', (
    tester,
  ) async {
    // Le serveur gagne un film entre le lancement et « Actualiser ».
    final routes = server;
    var added = false;
    var fullLists = 0;
    server = FakeAdapter((options) async {
      final query = options.uri.queryParameters;
      if (query['action'] == 'get_vod_streams' &&
          !query.containsKey('category_id')) {
        fullLists++;
        if (added) {
          final films = jsonDecode(_fixture('vod_streams')) as List<Object?>;
          films.add({
            'stream_id': 999,
            'name': 'Nouveauté (2026) FHD MULTI',
            'category_id': '148',
            'container_extension': 'mkv',
          });
          return ResponseBody.fromString(jsonEncode(films), 200);
        }
      }
      return routes.fetch(options, null, null);
    });
    await pumpApp(tester);
    expect(fullLists, 1);

    added = true;
    await tester.tap(find.byTooltip('Actualiser'));
    await settle(tester);
    for (var i = 0; i < 40 && fullLists < 2; i++) {
      await settle(tester);
    }
    expect(fullLists, 2, reason: 'la liste complète redemandée, une fois');

    await tester.tap(find.text('Recherche'));
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(SearchScreen),
        matching: find.byType(EditableText),
      ),
      'nouveaute',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(find.text('Nouveauté (2026)'), findsOneWidget);
  });

  testWidgets('téléphone : titre et boutons dans l\'en-tête, sans filtre', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(400, 800));
    // Pas de rail : les réglages restent dans l'en-tête.
    expect(find.byTooltip('Réglages'), findsOneWidget);
    expect(find.byTooltip('Actualiser'), findsOneWidget);
    expect(find.byTooltip('Filtrer'), findsNothing);
    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets('grand écran : réglages en bas du rail', (tester) async {
    await pumpApp(tester);
    final settings = find.text('Réglages');
    expect(settings, findsOneWidget);
    expect(
      find.descendant(of: find.byType(NavigationRail), matching: settings),
      findsOneWidget,
    );
    // Sous les onglets, en bas de l'écran.
    expect(
      tester.getTopLeft(settings).dy,
      greaterThan(tester.getTopLeft(find.text('Recherche')).dy),
    );
    expect(tester.getBottomLeft(settings).dy, greaterThan(800 - 100));
  });
}
