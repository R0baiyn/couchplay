import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:couchplay/catalog/catalog_screen.dart';
import 'package:couchplay/catalog/movie_screen.dart';
import 'package:couchplay/catalog/poster_grid.dart';
import 'package:couchplay/catalog/series_screen.dart';
import 'package:couchplay/focus_ring.dart';
import 'package:couchplay/library/library_store.dart';
import 'package:couchplay/search/search_screen.dart';

import 'package:couchplay/update/updater.dart';
import 'package:couchplay/update/windows_installer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';
import '../support/settle.dart';
import '../support/catalog_app.dart';

void main() {
  setUpCatalogApp();

  testWidgets('Films : catégories françaises, grille, puis fiche', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('FR · Drame'), findsOneWidget);
    expect(find.text('Films 4K'), findsOneWidget);
    expect(find.text('AR · ARABE أفلام عربية'), findsNothing);
    expect(find.text('VOST · Films'), findsNothing);
    // Grille de la première catégorie (le faux serveur renvoie la fixture),
    // les trois versions de « Horizon » en une seule affiche.
    expect(find.text('Horizon (2024)'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('catalog.poster.movies-144016')),
    );
    await settle(tester);

    expect(find.byType(MovieScreen), findsOneWidget);
    expect(find.textContaining('Réalisateur Fictif'), findsOneWidget);
    expect(find.text('2024  ·  1 h 50  ·  ★ 6.6'), findsOneWidget);

    // Échap ramène à la grille.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(MovieScreen), findsNothing);
    expect(find.text('Horizon (2024)'), findsOneWidget);
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
    await tester.tap(
      find.byKey(const ValueKey('catalog.poster.movies-144016')),
    );
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

  testWidgets(
    "place insuffisante au démarrage : la boîte une fois l'accueil devant",
    (tester) async {
      final found = Completer<StartupOffer?>();
      await pumpApp(
        tester,
        overrides: [
          // Seul « Annuler » est touché : rien n'est installé.
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
      final box = find.text('Place insuffisante');
      await tester.tap(
        find.byKey(const ValueKey('catalog.poster.movies-144016')),
      );
      await settle(tester);

      // Retenue pendant qu'une fiche est ouverte : rien par-dessus.
      found.complete(const ShortOfSpace(free: 572723200, needed: 583188918));
      await settle(tester);
      expect(find.byType(MovieScreen), findsOneWidget);
      expect(box, findsNothing);

      // De retour sur l'accueil : la boîte, puis « Annuler » la ferme.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(box, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('update.spaceCancel')));
      await settle(tester);
      expect(box, findsNothing);
    },
  );

  testWidgets('Séries : catégories, fiche, saisons et épisodes', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('shell.tabSeries')));
    await settle(tester);

    expect(find.text('Séries PLATEFORME A'), findsOneWidget);
    expect(find.text('Séries SUB-AR'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('catalog.poster.series-17')));
    await settle(tester);

    expect(find.byType(SeriesScreen), findsOneWidget);
    expect(find.text('Saison 1'), findsOneWidget);
    expect(find.text('Saison 2'), findsOneWidget);
    final firstEpisode = find.textContaining('1. Épisode 1');
    await tester.scrollUntilVisible(firstEpisode, 300);
    expect(firstEpisode, findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('catalog.seasonChip.2')),
      -300,
    );
    await tester.tap(find.byKey(const ValueKey('catalog.seasonChip.2')));
    await tester.pump();
    expect(firstEpisode, findsNothing);
    await tester.scrollUntilVisible(find.textContaining('1. Épisode 4'), 300);
    expect(find.textContaining('1. Épisode 4'), findsOneWidget);
  });

  testWidgets('écran étroit : catégorie en panneau, en-tête repliable', (
    tester,
  ) async {
    // Assez de films dans « FR · Drame » pour que sa grille défile sous
    // l'en-tête, sur un écran bas.
    final routes = server;
    final films = jsonDecode(fixture('vod_streams')) as List<Object?>
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
    expect(find.text('Horizon (2024)'), findsOneWidget);

    // Le bouton montre la catégorie choisie et ouvre le panneau ; toucher à
    // côté le ferme sans rien changer.
    final picker = find.byKey(const ValueKey('catalog.categoryPicker'));
    expect(find.widgetWithText(OutlinedButton, 'Films 4K'), findsOneWidget);
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
      find.byKey(const ValueKey('catalog.categorySheetTile.118')),
    );
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'FR · Drame'), findsOneWidget);

    // Descendre replie l'en-tête, remonter un peu le fait revenir.
    final refresh = find.byKey(const ValueKey('catalog.refresh')).hitTestable();
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
    expect(find.textContaining('Hors ligne : catalogue'), findsNothing);

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

    expect(find.textContaining('Hors ligne : catalogue'), findsOneWidget);
    expect(find.text('Horizon (2024)'), findsOneWidget);

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
    // Une catégorie de deux films : Horizon, puis Marée Haute.
    await openCategory(tester, '148');

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
        matching: find.text('Marée Haute (2024)'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('cocher un pays dans les réglages l\'affiche aussitôt', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('AR · ARABE أفلام عربية'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings.open')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('settings.catalog')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('catalog.tag.AR')));
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    // Les réglages sont une page : Échap revient au catalogue.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    await tester.scrollUntilVisible(
      find.text('AR · ARABE أفلام عربية'),
      200,
      // Pas celui du rail.
      scrollable: find
          .descendant(
            of: find.byType(CatalogScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('AR · ARABE أفلام عربية'), findsOneWidget);
  });

  testWidgets('« Actualiser » recharge catégories et grille sans les cacher', (
    tester,
  ) async {
    await pumpApp(tester);
    final fake = server as FakeAdapter;
    final before = fake.calls;

    await tester.tap(find.byKey(const ValueKey('catalog.refresh')));
    await tester.pump();
    // Pendant le rechargement, la grille reste là.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Horizon (2024)'), findsOneWidget);

    await settle(tester);
    expect(
      fake.calls,
      before + 2,
      reason: 'catégories et liste complète, une fois chacune',
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Horizon (2024)'), findsOneWidget);
  });

  testWidgets('tirer la grille vers le bas l\'actualise (toucher)', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(400, 800));
    final fake = server as FakeAdapter;
    final before = fake.calls;

    await tester.fling(
      find.byKey(const ValueKey('catalog.grid')),
      const Offset(0, 400),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(
      fake.calls,
      before + 2,
      reason: 'catégories et liste complète, une fois chacune',
    );
    expect(find.text('Horizon (2024)'), findsOneWidget);
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
      of: find.byKey(const ValueKey('search.field')),
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
    expect(find.text('Le Secret d\'Égypte (1998)'), findsOneWidget);
    expect(find.textContaining('Séries ('), findsNothing);

    await type('veil');
    expect(find.text('Séries (1)'), findsOneWidget);
    expect(find.text('Les Veilleurs'), findsOneWidget);

    // Une seule affiche pour les trois versions.
    await type('horizon');
    expect(find.text('Films (1)'), findsOneWidget);
    expect(find.text('Horizon (2024)'), findsOneWidget);

    await type('zzz');
    expect(find.text('Aucun résultat pour « zzz ».'), findsOneWidget);
  });

  testWidgets('Fiche : versions, la meilleure d\'abord, favori de la choisie', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(
      find.byKey(const ValueKey('catalog.poster.movies-144016')),
    );
    await settle(tester);

    ChoiceChip chip(String label) =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
    expect(chip('4K').selected, isTrue);
    expect(chip('FHD VF').selected, isFalse);
    expect(chip('HD VF').selected, isFalse);

    await tester.tap(find.byKey(const ValueKey('catalog.versionChip.144014')));
    await settle(tester);
    expect(chip('HD VF').selected, isTrue);
    expect(chip('4K').selected, isFalse);

    await tester.tap(find.byKey(const ValueKey('catalog.favorite')));
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
    await tester.tap(
      find.byKey(const ValueKey('catalog.poster.movies-144016')),
    );
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
      of: find.byKey(const ValueKey('search.field')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    expect(tester.widget<EditableText>(field).controller.text, isEmpty);
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
    await tester.tap(
      find.byKey(const ValueKey('catalog.poster.movies-144016')),
    );
    await settle(tester);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.text('Lecture'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('catalog.versionChip.144014')));
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
          final films = jsonDecode(fixture('vod_streams')) as List<Object?>;
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
    await tester.tap(find.byKey(const ValueKey('catalog.refresh')));
    await settle(tester);
    for (var i = 0; i < 40 && fullLists < 2; i++) {
      await settle(tester);
    }
    expect(fullLists, 2, reason: 'la liste complète redemandée, une fois');

    await tester.tap(find.byKey(const ValueKey('shell.tabSearch')));
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('search.field')),
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

  for (final (name, size, bar, width) in [
    ('rail', const Size(1280, 800), NavigationRail, 56.0),
    ('barre', const Size(400, 800), NavigationBar, 64.0),
  ]) {
    testWidgets('$name : l’anneau entoure l’icône de l’onglet, pas le libellé', (
      tester,
    ) async {
      await pumpApp(tester, size: size, openMovies: false);
      final ring = find
          .descendant(of: find.byType(bar), matching: find.byType(FocusRing))
          .first;
      // Un appui de touche passe en mode clavier, puis l'onglet prend le focus.
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      Focus.of(tester.element(ring)).requestFocus();
      await tester.pumpAndSettle();

      // La pastille de l'icône, comme le bouton Réglages du rail.
      expect(tester.getSize(ring), Size(width, 32));
      expect(
        tester.renderObject(ring),
        paints..rrect(
          rrect: RRect.fromRectAndRadius(
            (Offset.zero & Size(width, 32)).deflate(focusRing.width / 2),
            // Une pilule.
            Radius.circular((32 - focusRing.width) / 2),
          ),
          color: Colors.white,
          strokeWidth: 3,
        ),
      );
    });
  }
}
