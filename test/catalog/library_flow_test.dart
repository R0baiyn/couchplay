import 'dart:convert';
import 'dart:io';

import 'package:couchplay/catalog/movie_screen.dart';
import 'package:couchplay/catalog/series_screen.dart';
import 'package:couchplay/catalog/favorites_screen.dart';
import 'package:couchplay/catalog/history_screen.dart';
import 'package:couchplay/library/library_store.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/settle.dart';
import '../support/catalog_app.dart';

void main() {
  setUpCatalogApp();

  testWidgets("un favori ajouté sur une fiche apparaît sur l'accueil", (
    tester,
  ) async {
    await pumpApp(tester, openMovies: false);
    expect(
      find.byKey(const ValueKey('library.favoritesEmpty')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('shell.tabMovies')));
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey('catalog.poster.movies-144016')),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('catalog.favorite')));
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    // Retour sur l'accueil, sans redémarrer.
    await tester.tap(find.byKey(const ValueKey('shell.tabHome')));
    await settle(tester);
    expect(find.byKey(const ValueKey('library.favoritesEmpty')), findsNothing);
    expect(find.text('Horizon (2024)'), findsOneWidget);

    // « Tout voir » : grille filtrable.
    await tester.tap(find.byKey(const ValueKey('library.favoritesAll')));
    await settle(tester);
    expect(find.byType(FavoritesScreen), findsOneWidget);
    expect(find.text('Horizon (2024)'), findsOneWidget);
    // Le favori est la version proposée sur la fiche : la meilleure.
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('library.kindFilter.series')));
    await settle(tester);
    expect(find.text('Horizon (2024)'), findsNothing);
    expect(find.byKey(const ValueKey('library.favoritesNone')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('library.kindFilter.movies')));
    await settle(tester);
    expect(find.text('Horizon (2024)'), findsOneWidget);

    // La fiche s'ouvre depuis la grille ; retirer le favori le fait
    // disparaître au retour.
    await tester.tap(
      find.byKey(const ValueKey('catalog.poster.movies-144016')),
    );
    await settle(tester);
    expect(find.byType(MovieScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChoiceChip, skipOffstage: true),
        matching: find.text('4K'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('catalog.favorite')));
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Horizon (2024)'), findsNothing);
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
              'name': 'Horizon (2024) HD VF',
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
    await tester.tap(
      find.byKey(const ValueKey('catalog.poster.movies-144016')),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('catalog.play')));
    await settle(tester);

    expect(find.text('Reprendre à 12:34'), findsOneWidget);
    expect(find.text('Recommencer'), findsOneWidget);
    // Fermer sans choisir laisse sur la fiche.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Reprendre à 12:34'), findsNothing);
    expect(find.byType(MovieScreen), findsOneWidget);
  });

  testWidgets('flèches : → depuis un épisode mène à son menu', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('shell.tabSeries')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('catalog.poster.series-17')));
    await settle(tester);
    final firstEpisode = find.textContaining('1. Épisode 1');
    await tester.scrollUntilVisible(firstEpisode, 300);

    Focus.of(tester.element(firstEpisode)).requestFocus();
    await tester.pump();
    // Le bouton « Télécharger » est entre l'épisode et son menu.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<PopupMenuButton<bool>>()
          ?.tooltip,
      "Plus d'options",
    );
  });

  testWidgets('un épisode se marque vu ou non vu, et le reste', (tester) async {
    Future<void> openVeilleurs() async {
      await tester.tap(find.byKey(const ValueKey('shell.tabSeries')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('catalog.poster.series-17')));
      await settle(tester);
    }

    final firstEpisode = find.textContaining('1. Épisode 1');
    final seen = find.byIcon(Icons.check_circle);

    await pumpApp(tester);
    await openVeilleurs();
    await tester.scrollUntilVisible(firstEpisode, 300);
    expect(seen, findsNothing);
    await tester.tap(find.byKey(const ValueKey('catalog.episodeMenu.6912')));
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey('catalog.episodeToggleWatched')),
    );
    await settle(tester);
    expect(seen, findsOneWidget);

    // Nouveau lancement, une fois l'écriture faite : toujours vu, et on peut
    // l'annuler.
    bool watched(Map<Object?, Object?> progress) =>
        progress.values.any((e) => (e as Map)['watched'] == true);
    expect(watched(await savedProgress(tester, watched)), isTrue);
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester);
    await openVeilleurs();
    await tester.scrollUntilVisible(firstEpisode, 300);
    expect(seen, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('catalog.episodeMenu.6912')));
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey('catalog.episodeToggleWatched')),
    );
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
      'name': 'Les Veilleurs',
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
              'name': 'Horizon (2024) HD VF',
              'extension': 'mp4',
              'position': 754,
              'duration': 6600,
              'updatedAt': '2026-01-01T00:00:00Z',
            },
            'movie:144015': {
              'name': 'Horizon (2024) FHD VF',
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
    expect(inContinue('Les Veilleurs · S1E2'), findsOneWidget);
    expect(inContinue('Les Veilleurs · S1E1'), findsNothing);
    expect(inContinue('Horizon (2024) HD VF'), findsOneWidget);
    expect(inContinue('Horizon (2024) FHD VF'), findsNothing);
    expect(
      tester.getTopLeft(inContinue('Les Veilleurs · S1E2')).dx,
      lessThan(tester.getTopLeft(inContinue('Horizon (2024) HD VF')).dx),
    );

    // Appui long, « Retirer » : l'entrée part, la progression reste.
    await tester.longPress(
      find.byKey(const ValueKey('library.continueTile.movie:144014')),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('confirm.action')));
    await settle(tester);
    expect(inContinue('Horizon (2024) HD VF'), findsNothing);
    expect(inContinue('Les Veilleurs · S1E2'), findsOneWidget);
    final progress = await savedProgress(
      tester,
      (progress) => (progress['movie:144014'] as Map?)?['hidden'] == true,
    );
    final movie = progress['movie:144014'] as Map?;
    expect(movie?['position'], 754);
    expect(movie?['hidden'], isTrue);
  });

  testWidgets('Historique : liste, fiche, retrait, effacement, état vide', (
    tester,
  ) async {
    File('${root.path}/accounts/compte/library.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'favorites': {
            'movie:144014': {
              'name': 'Horizon (2024) HD VF',
              'addedAt': '2026-01-01T00:00:00Z',
            },
          },
          'progress': {
            'movie:144014': {
              'name': 'Horizon (2024) HD VF',
              'extension': 'mp4',
              'position': 754,
              'duration': 6600,
              'hidden': true,
              'updatedAt': '2026-01-01T00:00:00Z',
            },
            'movie:144015': {
              'name': 'Horizon (2024) FHD VF',
              'extension': 'mkv',
              'position': 6600,
              'duration': 6600,
              'watched': true,
              'updatedAt': '2026-01-04T00:00:00Z',
            },
            'episode:6912': {
              'seriesId': '1',
              'season': 1,
              'episode': 1,
              'name': 'Les Veilleurs',
              'extension': 'mkv',
              'position': 600,
              'duration': 2700,
              'updatedAt': '2026-01-02T00:00:00Z',
            },
          },
        }),
      );
    await pumpApp(tester, size: const Size(1280, 1500), openMovies: false);

    // L'accueil : la rangée « Vus » (seulement les vus), pas de rangée
    // « Historique », et le bouton « Historique » tout en bas.
    expect(find.text('Vus'), findsOneWidget);
    for (final key in [
      'history:movie:144014',
      'history:movie:144015',
      'history:episode:6912',
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
    }
    expect(
      find.byKey(const ValueKey('library.seenTile.movie:144015')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('library.seenTile.movie:144014')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('library.seenTile.episode:6912')),
      findsNothing,
    );
    final button = find.byKey(const ValueKey('library.historyButton'));
    expect(button, findsOneWidget);
    for (final above in [find.text('Vus'), find.text('Ma liste')]) {
      expect(
        tester.getTopLeft(button).dy,
        greaterThan(tester.getTopLeft(above).dy),
      );
    }

    // Une affiche de « Vus » ouvre la fiche du film.
    await tester.tap(
      find.byKey(const ValueKey('library.seenTile.movie:144015')),
    );
    await settle(tester);
    expect(find.byType(MovieScreen), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    await tester.tap(button);
    await settle(tester);
    expect(find.byType(HistoryScreen), findsOneWidget);
    // Tout y est, retiré de « Continuer » et vu compris, le plus récent
    // d'abord.
    final vu = tester.getTopLeft(find.text('Horizon (2024) FHD VF')).dy;
    final episode = tester.getTopLeft(find.text('Les Veilleurs · S1E1')).dy;
    final retire = tester.getTopLeft(find.text('Horizon (2024) HD VF')).dy;
    expect(vu, lessThan(episode));
    expect(episode, lessThan(retire));
    expect(find.textContaining('04/01/2026 · Vu'), findsOneWidget);
    expect(find.textContaining('02/01/2026 · 10:00 / 45:00'), findsOneWidget);

    // Un épisode ouvre la fiche de sa série.
    await tester.tap(
      find.byKey(const ValueKey('library.historyRow.episode:6912')),
    );
    await settle(tester);
    expect(find.byType(SeriesScreen), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    // Retirer une ligne : sa progression part, les autres restent.
    await tester.tap(
      find.byKey(const ValueKey('library.historyRemove.movie:144015')),
    );
    await settle(tester);
    expect(find.text('Horizon (2024) FHD VF'), findsNothing);
    expect(find.text('Les Veilleurs · S1E1'), findsOneWidget);
    final progress = await savedProgress(
      tester,
      (progress) =>
          progress.isNotEmpty && !progress.containsKey('movie:144015'),
    );
    expect(progress.keys, unorderedEquals(['movie:144014', 'episode:6912']));

    // Effacer : confirmation, état vide, favoris intacts.
    await tester.tap(find.byKey(const ValueKey('library.historyClear')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('confirm.cancel')));
    await settle(tester);
    expect(find.text('Les Veilleurs · S1E1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('library.historyClear')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('confirm.action')));
    await settle(tester);
    expect(find.byKey(const ValueKey('library.historyEmpty')), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HistoryScreen)),
    );
    expect(container.read(libraryProvider).favorites.keys, ['movie:144014']);

    // Sans historique, plus de bouton sur l'accueil.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Historique'), findsNothing);
    expect(find.text('Vus'), findsNothing);
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
              'name': 'Les Veilleurs',
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
    final next = inContinue('Les Veilleurs · S1E3');
    for (var i = 0; i < 20 && next.evaluate().isEmpty; i++) {
      await settle(tester);
    }

    expect(find.text('Continuer à regarder'), findsOneWidget);
    expect(next, findsOneWidget);
    expect(inContinue('Les Veilleurs · S1E2'), findsNothing);
  });

  testWidgets('série finie, rien à suivre : pas d\'en-tête « Continuer »', (
    tester,
  ) async {
    File('${root.path}/accounts/compte/library.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'progress': {
            'episode:6923': {
              'seriesId': '1',
              'season': 2,
              'episode': 3,
              'name': 'Les Veilleurs',
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
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }

    expect(find.text('Ma liste'), findsOneWidget);
    expect(find.text('Continuer à regarder'), findsNothing);
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
              'name': 'Horizon (2024) HD VF',
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
    await tester.tap(
      find.byKey(const ValueKey('catalog.poster.movies-144016')),
    );
    await settle(tester);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'HD VF'))
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('catalog.favorite')));

    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('chaînes récentes seules : « Historique » permet de les '
      'effacer, les chaînes favorites restent', (tester) async {
    File('${root.path}/accounts/compte/library.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'channels': {
            'favorites': [
              {'id': '9002', 'name': 'Chaîne 2', 'at': '2026-11-25T20:00:00Z'},
            ],
            'recent': [
              {'id': '9001', 'name': 'Chaîne 1', 'at': '2026-11-25T20:00:00Z'},
            ],
          },
        }),
      );
    await pumpApp(tester, openMovies: false);
    expect(find.byKey(const ValueKey('live.recentRow')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('library.historyButton')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('library.historyClear')));
    await settle(tester);
    expect(find.textContaining('chaînes récentes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm.action')));
    await settle(tester);
    final library = ProviderScope.containerOf(
      tester.element(find.byType(HistoryScreen)),
    ).read(libraryProvider);
    expect(library.recentChannels, isEmpty);
    expect(library.channelFavorites.single.id, '9002');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byKey(const ValueKey('live.recentRow')), findsNothing);
    expect(find.byKey(const ValueKey('library.historyButton')), findsNothing);
  });
}
