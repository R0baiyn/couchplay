import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/catalog/downloads_screen.dart';
import 'package:couchplay/catalog/home_screen.dart';
import 'package:couchplay/live/live_screen.dart';
import 'package:couchplay/settings/settings_screen.dart';
import 'package:couchplay/television.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/catalog_app.dart';
import 'support/fake_downloads.dart';
import 'support/real_font.dart';
import 'support/settle.dart';

void main() {
  setUpCatalogApp();
  // Vraies largeurs de lettres : les libellés des onglets doivent tenir.
  setUpAll(loadRoboto);

  testWidgets('rail peu haut : Réglages ne recouvre aucun onglet', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1000, 260), openMovies: false);
    Finder inRail(Finder f) =>
        find.descendant(of: find.byType(NavigationRail), matching: f);
    final settings = tester.getRect(inRail(find.byType(SettingsButton)));
    for (final label in ['Accueil', 'Films', 'Séries', 'TV', 'Recherche']) {
      final tab = tester.getRect(inRail(find.text(label)));
      expect(settings.overlaps(tab), isFalse, reason: label);
    }
  });

  for (final (name, size) in [
    ('rail', const Size(1280, 800)),
    ('barre du bas', const Size(360, 740)),
  ]) {
    testWidgets('$name : onglet Hors ligne ouvert, rien ne déborde', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: size,
        openMovies: false,
        overrides: [downloadsProvider.overrideWith(FakeDownloads.new)],
      );
      // Le libellé tient sur une ligne : aussi haut que celui de « Films ».
      expect(
        tester
            .getSize(find.text(size.width < 600 ? 'Recherche' : 'Hors ligne'))
            .height,
        tester.getSize(find.text('Films')).height,
      );
      // Écran étroit : plus dans la barre, une icône en haut (D-082).
      await tester.tap(
        find.byKey(
          ValueKey(size.width < 600 ? 'shell.offline' : 'shell.tabDownloads'),
        ),
      );
      await settle(tester);
      expect(find.byType(DownloadsScreen), findsOneWidget);
      // Le titre de l'écran garde son nom complet ; sur téléphone, celui
      // de l'onglet (D-061).
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(
            size.width < 600 ? 'Hors ligne' : 'Téléchargements',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Aucun téléchargement'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('le rail a la même largeur avec ou sans l\'onglet Hors ligne', (
    tester,
  ) async {
    Future<double> railWidth({required bool tv}) async {
      await pumpApp(
        tester,
        size: const Size(1280, 800),
        openMovies: false,
        overrides: [
          televisionProvider.overrideWithValue(tv),
          downloadsProvider.overrideWith(FakeDownloads.new),
        ],
      );
      return tester.getSize(find.byType(NavigationRail)).width;
    }

    final five = await railWidth(tv: false);
    final four = await railWidth(tv: true);
    expect(five, four);
  });

  testWidgets('Android TV : pas d onglet Hors ligne', (tester) async {
    await pumpApp(
      tester,
      openMovies: false,
      overrides: [
        televisionProvider.overrideWithValue(true),
        downloadsProvider.overrideWith(FakeDownloads.new),
      ],
    );
    expect(find.text('Recherche'), findsOneWidget);
    expect(find.text('Hors ligne'), findsNothing);
    expect(find.byKey(const ValueKey('shell.tabDownloads')), findsNothing);
  });

  // Chaque onglet garde sa Key, choisi ou non : une seule par onglet.
  for (final (name, size) in [
    ('rail', const Size(1280, 800)),
    ('barre du bas', const Size(360, 740)),
  ]) {
    testWidgets('$name : la Key de chaque onglet reste, choisi ou non', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: size,
        openMovies: false,
        overrides: [downloadsProvider.overrideWith(FakeDownloads.new)],
      );
      final tabs = [
        'shell.tabHome',
        'shell.tabMovies',
        'shell.tabSeries',
        'shell.tabLive',
        'shell.tabSearch',
        if (size.width >= 600) 'shell.tabDownloads',
      ];
      void expectEachKeyOnce(String selected) {
        for (final tab in tabs) {
          expect(
            find.byKey(ValueKey(tab)),
            findsOneWidget,
            reason: '$tab, $selected choisi',
          );
        }
      }

      // L'app s'ouvre sur l'accueil.
      expectEachKeyOnce('shell.tabHome');
      for (final tab in tabs.skip(1)) {
        await tester.tap(find.byKey(ValueKey(tab)));
        await settle(tester);
        expectEachKeyOnce(tab);
      }
    });
  }

  // Écran étroit : pas de rail, chaque onglet porte son bouton Réglages dans
  // l'en-tête, passé par la coquille.
  testWidgets("barre du bas : Réglages s'ouvre depuis chaque onglet", (
    tester,
  ) async {
    await pumpApp(
      tester,
      size: const Size(360, 740),
      openMovies: false,
      overrides: [downloadsProvider.overrideWith(FakeDownloads.new)],
    );
    // L'app s'ouvre sur l'accueil.
    for (final tab in [
      null,
      'shell.tabMovies',
      'shell.tabSeries',
      'shell.tabLive',
      'shell.tabSearch',
    ]) {
      if (tab != null) {
        await tester.tap(find.byKey(ValueKey(tab)));
        await settle(tester);
      }
      await tester.tap(find.byKey(const ValueKey('settings.open')));
      await settle(tester);
      expect(find.byType(SettingsScreen), findsOneWidget, reason: tab);
      await tester.pageBack();
      await settle(tester);
      expect(find.byType(SettingsScreen), findsNothing, reason: tab);
    }
  });

  for (final (name, size) in [
    ('rail', const Size(1280, 800)),
    ('barre du bas', const Size(360, 740)),
  ]) {
    testWidgets('$name : TV entre Séries et Recherche', (tester) async {
      await pumpApp(
        tester,
        size: size,
        openMovies: false,
        overrides: [downloadsProvider.overrideWith(FakeDownloads.new)],
      );
      double at(String key) {
        final center = tester.getCenter(find.byKey(ValueKey(key)));
        return size.width < 600 ? center.dx : center.dy;
      }

      expect(at('shell.tabLive'), greaterThan(at('shell.tabSeries')));
      expect(at('shell.tabLive'), lessThan(at('shell.tabSearch')));
      await tester.tap(find.byKey(const ValueKey('shell.tabLive')));
      await settle(tester);
      expect(find.byType(LiveScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('live.channel.9001')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // L'app s'ouvre sur l'accueil ; `null` : y rester.
  const headerTabs = [
    null,
    'shell.tabMovies',
    'shell.tabSeries',
    'shell.tabLive',
  ];
  final offline = find.byKey(const ValueKey('shell.offline'));

  Future<void> open(WidgetTester tester, String? tab) async {
    if (tab == null) return;
    await tester.tap(find.byKey(ValueKey(tab)));
    await settle(tester);
  }

  testWidgets('écran étroit : « Hors ligne » en haut d\'Accueil, Films, Séries '
      'et TV, plus dans la barre', (tester) async {
    await pumpApp(
      tester,
      size: const Size(360, 740),
      openMovies: false,
      overrides: [downloadsProvider.overrideWith(FakeDownloads.new)],
    );
    expect(find.byKey(const ValueKey('shell.tabDownloads')), findsNothing);
    expect(find.text('Hors ligne'), findsNothing);
    for (final tab in headerTabs) {
      await open(tester, tab);
      expect(offline, findsOneWidget, reason: tab);
      await tester.tap(offline);
      await settle(tester);
      expect(find.byType(DownloadsScreen), findsOneWidget, reason: tab);
      await tester.pageBack();
      await settle(tester);
      expect(find.byType(DownloadsScreen), findsNothing, reason: tab);
    }
    expect(tester.takeException(), isNull);
  });

  for (final tv in [false, true]) {
    testWidgets('${tv ? 'TV' : 'écran large'} : pas d\'icône « Hors ligne » en '
        'haut', (tester) async {
      await pumpApp(
        tester,
        openMovies: false,
        overrides: [
          televisionProvider.overrideWithValue(tv),
          downloadsProvider.overrideWith(FakeDownloads.new),
        ],
      );
      expect(
        find.byKey(const ValueKey('shell.tabDownloads')),
        tv ? findsNothing : findsOneWidget,
      );
      for (final tab in headerTabs) {
        await open(tester, tab);
        expect(offline, findsNothing, reason: tab);
      }
    });
  }

  testWidgets('fenêtre rétrécie sur « Hors ligne » : retour à l\'Accueil', (
    tester,
  ) async {
    await pumpApp(
      tester,
      openMovies: false,
      overrides: [downloadsProvider.overrideWith(FakeDownloads.new)],
    );
    await tester.tap(find.byKey(const ValueKey('shell.tabDownloads')));
    await settle(tester);

    tester.view.physicalSize = const Size(360, 740);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(DownloadsScreen), findsNothing);
    expect(offline, findsOneWidget);
  });
}
