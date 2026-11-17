import 'dart:async';
import 'dart:convert';

import 'package:couchplay/catalog/catalog_settings_screen.dart';
import 'package:couchplay/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_app.dart';
import '../support/fake_server.dart';
import '../support/settle.dart';

void main() {
  setUpCatalogApp();

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
