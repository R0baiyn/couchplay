import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:couchplay/home_shell.dart';
import 'package:couchplay/catalog/movie_screen.dart';
import 'package:couchplay/catalog/series_screen.dart';
import 'package:couchplay/library/history_screen.dart';
import 'package:couchplay/library/library.dart';

import 'package:couchplay/server/models.dart';
import 'package:couchplay/settings/settings_screen.dart';
import 'package:couchplay/television.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';
import '../support/settle.dart';
import '../support/catalog_app.dart';

void main() {
  setUpCatalogApp();

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
      await tester.tap(find.byKey(const ValueKey('shell.tabSearch')));
      await settle(tester);
      expect(find.byType(EditableText), findsNothing);

      // La case de recherche a le focus ; OK ouvre la saisie.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'horizon');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(find.text('Horizon (2024)'), findsOneWidget);
    },
  );

  group('TV, à la télécommande', () {
    /// Une grille de 40 films dans « Films 4K », et l'app à la taille d'une
    /// TV (960 × 540).
    Future<void> pumpTv(WidgetTester tester, {String? seriesInfo}) async {
      final film = (jsonDecode(fixture('vod_streams')) as List).first as Map;
      server = FakeAdapter.routes({
        '': activeAccountJson,
        'get_vod_categories': fixture('vod_categories'),
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
        'get_vod_info': fixture('vod_info'),
        'get_series_categories': fixture('series_categories'),
        'get_series': fixture('series'),
        'get_series_info': seriesInfo ?? fixture('series_info'),
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
      expect(focused(), isNot('Film 1 (2020)'), reason: 'une rangée plus bas');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      final visited = focused();

      // ← au bord gauche : l'onglet choisi, pas l'élément le plus proche.
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
      expect(focused(), visited);
    });

    /// Une série de 30 épisodes : la liste dépasse l'écran.
    String longSeries() {
      final info = jsonDecode(fixture('series_info')) as Map<String, Object?>;
      final first =
          ((info['episodes']! as Map)['1']! as List).first
              as Map<String, Object?>;
      return jsonEncode({
        ...info,
        'episodes': {
          '1': [
            for (var i = 1; i <= 30; i++)
              {
                ...first,
                'id': '${7000 + i}',
                'episode_num': i,
                'title': 'Épisode $i',
              },
          ],
        },
      });
    }

    testWidgets(
      'fiche série : le focus descend dans les épisodes, la page suit',
      (tester) async {
        await pumpTv(tester, seriesInfo: longSeries());
        await tester.tap(find.byKey(const ValueKey('shell.tabSeries')));
        await settle(tester);
        await tester.tap(
          find.byKey(const ValueKey('catalog.poster.series-17')),
        );
        await settle(tester);
        expect(find.byType(SeriesScreen), findsOneWidget);

        var guard = 0;
        while (!(focused() ?? '').startsWith('1. ') && guard++ < 20) {
          await press(tester, LogicalKeyboardKey.arrowDown);
        }
        for (var i = 0; i < 12; i++) {
          await press(tester, LogicalKeyboardKey.arrowDown);
        }
        final focus = FocusManager.instance.primaryFocus!;
        final box = focus.context!.findRenderObject()! as RenderBox;
        final top = box.localToGlobal(Offset.zero).dy;
        expect(focused(), startsWith('13. '));
        expect(
          top,
          inInclusiveRange(0, 540),
          reason: "l'épisode est à l'écran",
        );

        // Un écran par-dessus (le lecteur), puis retour : même place.
        unawaited(
          Navigator.of(tester.element(find.byType(SeriesScreen))).push(
            MaterialPageRoute<void>(builder: (_) => const Text('lecteur')),
          ),
        );
        await settle(tester);
        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(focused(), startsWith('13. '));
        final back = FocusManager.instance.primaryFocus!.context!;
        expect(
          (back.findRenderObject()! as RenderBox).localToGlobal(Offset.zero).dy,
          inInclusiveRange(0, 540),
        );
      },
    );

    testWidgets(
      "retour sur l'Accueil après « Effacer » : les flèches répondent",
      (tester) async {
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
        await pumpTv(tester);
        // Jusqu'au bouton « Historique », tout en bas, puis l'écran, puis
        // effacer.
        await press(tester, LogicalKeyboardKey.arrowRight);
        for (var i = 0; i < 6 && focused() != 'Historique'; i++) {
          await press(tester, LogicalKeyboardKey.arrowDown);
        }
        expect(focused(), 'Historique');
        await press(tester, LogicalKeyboardKey.select);
        expect(find.byType(HistoryScreen), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('library.historyClear')));
        await settle(tester);
        expect(focused(), 'Annuler');
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focused(), 'Effacer');
        await press(tester, LogicalKeyboardKey.select);
        expect(find.text("Rien regardé pour l'instant"), findsOneWidget);
        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(find.byType(HistoryScreen), findsNothing);
        expect(find.text('Historique'), findsNothing);

        // Les flèches doivent encore mener quelque part : un élément de
        // l'Accueil (pas la zone seule) a le focus, et ↓ le déplace.
        final node = FocusManager.instance.primaryFocus;
        expect(node, isNotNull);
        expect(node!.context, isNotNull);
        await press(tester, LogicalKeyboardKey.arrowDown);
        final moved = FocusManager.instance.primaryFocus;
        expect(
          moved is FocusScopeNode,
          isFalse,
          reason: 'un élément a le focus',
        );
        // Rien à atteindre dans l'Accueil vidé : le rail reprend le focus.
        expect(focused(), 'Accueil');
      },
    );

    testWidgets(
      "fiche série ouverte sur un épisode : page défilée, focus dessus",
      (tester) async {
        await pumpTv(tester, seriesInfo: longSeries());
        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeShell)),
        );
        expect(container, isNotNull);
        unawaited(
          Navigator.of(tester.element(find.byType(HomeShell))).push(
            MaterialPageRoute<void>(
              builder: (_) => const SeriesScreen(
                item: CatalogItem(
                  kind: ContentKind.series,
                  id: '1',
                  name: 'Les Veilleurs',
                ),
                episode: PlayItem.episode(
                  id: '7025',
                  extension: 'mkv',
                  name: 'Les Veilleurs',
                  seriesId: '1',
                  season: 1,
                  episode: 25,
                ),
              ),
            ),
          ),
        );
        await settle(tester);
        for (var i = 0; i < 20 && focused() == null; i++) {
          await settle(tester);
        }

        expect(focused(), startsWith('25. '));
        final box =
            FocusManager.instance.primaryFocus!.context!.findRenderObject()!
                as RenderBox;
        expect(
          box.localToGlobal(Offset.zero).dy,
          inInclusiveRange(0, 540),
          reason: "l'épisode est à l'écran",
        );
      },
    );

    testWidgets('retour depuis un onglet : le focus sur « Accueil »', (
      tester,
    ) async {
      await pumpTv(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), 'Film 0 (2020)');

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(focused(), 'Accueil', reason: 'depuis la grille');

      // Depuis le rail aussi : le focus suit l'onglet choisi.
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      expect(focused(), 'Films');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(focused(), 'Accueil', reason: 'depuis le rail');
    });

    testWidgets('Accueil : retour quitte seulement au 2e appui en 2 s', (
      tester,
    ) async {
      await pumpTv(tester);
      const message = 'Appuie encore sur retour pour quitter';
      // Bouton retour d'Android, sans attendre : la fenêtre est de 2 s.
      Future<bool> back() async {
        final handled = await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        return handled;
      }

      // Le lecteur (ici un écran qui en tient lieu) ouvert depuis l'Accueil :
      // un retour le ferme seul, sans armer la sortie.
      unawaited(
        Navigator.of(
          tester.element(find.byType(HomeShell)),
        ).push(MaterialPageRoute<void>(builder: (_) => const Text('lecteur'))),
      );
      await settle(tester);
      expect(await back(), isTrue);
      await settle(tester);
      expect(find.text('lecteur'), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);

      expect(await back(), isTrue, reason: '1er appui : l\'app reste');
      expect(find.text(message), findsOneWidget);
      expect(await back(), isFalse, reason: '2e appui en 2 s : quitte');

      // Passé 2 s, il faut de nouveau deux appuis.
      await tester.pump(const Duration(seconds: 3));
      expect(await back(), isTrue);
      await tester.pump(const Duration(seconds: 3));
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

      // ↑ mène à la barre du haut, et la fiche remonte tout en haut.
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(tester.getTopLeft(find.text('Lecture')).dy, before);
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
    await tester.tap(
      find.byKey(const ValueKey('catalog.poster.movies-144016')),
    );
    await settle(tester);
    expect(find.byType(MovieScreen), findsOneWidget);
    expect(await back(), isTrue);
    expect(find.byType(MovieScreen), findsNothing);
    expect(rail().selectedIndex, 1);

    // Retour de l'onglet vers l'Accueil : déjà vérifié par le test du focus TV.
    await tester.tap(find.byKey(const ValueKey('shell.tabHome')));
    await settle(tester);
    expect(rail().selectedIndex, 0);

    // À l'Accueil, retour quitte l'app (le système reprend la main).
    expect(await back(), isFalse);
  });
}
