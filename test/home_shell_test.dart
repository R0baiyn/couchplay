import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/downloads/downloads_screen.dart';
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
    for (final label in ['Accueil', 'Films', 'Séries', 'Recherche']) {
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
        tester.getSize(find.text('Hors ligne')).height,
        tester.getSize(find.text('Films')).height,
      );
      await tester.tap(find.byKey(const ValueKey('shell.tabDownloads')));
      await settle(tester);
      expect(find.byType(DownloadsScreen), findsOneWidget);
      // Le titre de l'écran garde son nom complet.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Téléchargements'),
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
}
