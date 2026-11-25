import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:couchplay/catalog/catalog_settings_screen.dart';
import 'package:couchplay/home_shell.dart';
import 'package:couchplay/live/live_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_app.dart';
import '../support/fake_server.dart';
import '../support/settle.dart';

void main() {
  setUpCatalogApp();

  Future<void> openSettings(WidgetTester tester) async {
    unawaited(
      Navigator.of(tester.element(find.byType(HomeShell))).push(
        MaterialPageRoute<void>(builder: (_) => const CatalogSettingsScreen()),
      ),
    );
    await settle(tester);
  }

  Finder byKey(String key) => find.byKey(ValueKey(key));

  testWidgets('sans section injectée : Films et Séries seuls', (tester) async {
    await pumpApp(tester, openMovies: false);
    await openSettings(tester);
    // Sous le bas de l'écran : cherché aussi hors champ.
    expect(
      find.byKey(
        const ValueKey('catalog.kindTile.series'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.text('Chaînes', skipOffstage: false), findsNothing);
  });

  testWidgets('section « Chaînes » injectée : une case cochée est gardée', (
    tester,
  ) async {
    await pumpApp(
      tester,
      openMovies: false,
      overrides: [
        catalogSettingsSectionsProvider.overrideWithValue(const [
          LiveCategorySettings(),
        ]),
      ],
    );
    await openSettings(tester);
    // La section est sous le bas de l'écran : `settle` ne voit pas son
    // chargement (lecture du cache, isolate), attendu ici.
    final loading = find.text('Chargement…', skipOffstage: false);
    for (var i = 0; i < 100 && loading.evaluate().isNotEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      // Le client espace ses requêtes : l'horloge factice avance aussi.
      await tester.pump(const Duration(milliseconds: 50));
    }
    // 13 catégories, 8 françaises : les autres sont masquées par défaut.
    expect(
      find.text('8 affichées sur 13', skipOffstage: false),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(byKey('live.settingsTile'), 200);
    await tester.tap(byKey('live.settingsTile'));
    await settle(tester);

    final belgium = byKey('live.categoryCheck.60');
    await tester.scrollUntilVisible(belgium, 100);
    await tester.ensureVisible(belgium);
    await settle(tester);
    expect(tester.widget<CheckboxListTile>(belgium).value, isFalse);
    await tester.tap(belgium);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(belgium).value, isTrue);
    final saved = await tester.runAsync(
      () =>
          File('${root.path}/accounts/compte/catalog_settings.json')
              .readAsString(),
    );
    expect(saved, contains('"live:60":true'));
  });

  testWidgets('les chaînes en échec : « Réessayer », sans bloquer Films et '
      'Séries', (tester) async {
    server = FakeAdapter.routes({
      '': activeAccountJson,
      'get_vod_categories': fixture('vod_categories'),
      'get_vod_streams': fixture('vod_streams'),
      'get_series_categories': fixture('series_categories'),
      'get_series': fixture('series'),
    });
    await pumpApp(
      tester,
      openMovies: false,
      overrides: [
        catalogSettingsSectionsProvider.overrideWithValue(const [
          LiveCategorySettings(),
        ]),
      ],
    );
    await openSettings(tester);
    expect(
      find.byKey(
        const ValueKey('catalog.kindTile.movies'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(byKey('live.settingsError'), 100);
    expect(byKey('live.settingsError'), findsOneWidget);
  });

  testWidgets('500 catégories : seules les cases visibles sont construites, '
      'et elles se cochent', (tester) async {
    final categories = jsonEncode([
      for (var i = 0; i < 500; i++)
        {'category_id': '$i', 'category_name': 'FR · Catégorie $i'},
    ]);
    server = FakeAdapter.routes({
      '': activeAccountJson,
      'get_vod_categories': categories,
      'get_vod_streams': '[]',
      'get_series_categories': '[]',
      'get_series': '[]',
    });
    await pumpApp(tester, openMovies: false);
    unawaited(
      Navigator.of(tester.element(find.byType(HomeShell))).push(
        MaterialPageRoute<void>(builder: (_) => const CatalogSettingsScreen()),
      ),
    );
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('catalog.kindTile.movies')));
    await settle(tester);
    expect(
      find.byType(CheckboxListTile, skipOffstage: false).evaluate().length,
      lessThan(60),
    );

    final first = find.byKey(const ValueKey('catalog.categoryCheck.movies.0'));
    expect(tester.widget<CheckboxListTile>(first).value, isTrue);
    await tester.tap(first);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(first).value, isFalse);
    expect(find.text('499 affichées sur 500'), findsOneWidget);
  });
}
