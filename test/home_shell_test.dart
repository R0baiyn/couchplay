import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/downloads/downloads_screen.dart';
import 'package:couchplay/settings/settings_screen.dart';
import 'package:couchplay/television.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/catalog_app.dart';
import 'support/fake_downloads.dart';
import 'support/settle.dart';

void main() {
  setUpCatalogApp();

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
    testWidgets('$name : onglet Téléchargements ouvert, rien ne déborde', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: size,
        openMovies: false,
        overrides: [downloadsProvider.overrideWith(FakeDownloads.new)],
      );
      await tester.tap(find.text('Téléchargements'));
      await settle(tester);
      expect(find.byType(DownloadsScreen), findsOneWidget);
      expect(find.text('Aucun téléchargement'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Android TV : pas d onglet Téléchargements', (tester) async {
    await pumpApp(
      tester,
      openMovies: false,
      overrides: [
        televisionProvider.overrideWithValue(true),
        downloadsProvider.overrideWith(FakeDownloads.new),
      ],
    );
    expect(find.text('Recherche'), findsOneWidget);
    expect(find.text('Téléchargements'), findsNothing);
    expect(find.byIcon(Icons.download_outlined), findsNothing);
  });
}
