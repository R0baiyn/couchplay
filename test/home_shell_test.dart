import 'package:couchplay/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/catalog_app.dart';

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
}
