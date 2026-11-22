import 'dart:async';

import 'package:couchplay/catalog/catalog_index.dart';
import 'package:couchplay/catalog/catalog_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_app.dart';
import '../support/fake_server.dart';
import '../support/settle.dart';

void main() {
  setUpCatalogApp();

  testWidgets('Recherche : champ, résultats, rien trouvé, effacer', (
    tester,
  ) async {
    await pumpApp(tester, openMovies: false);
    await tester.tap(find.byKey(const ValueKey('shell.tabSearch')));
    await settle(tester);

    final field = find.byKey(const ValueKey('search.field'));
    Future<void> type(String text) async {
      await tester.enterText(field, text);
      // La recherche part 300 ms après la dernière frappe.
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
    }

    // Champ vide : invitation, pas de croix.
    expect(find.byKey(const ValueKey('search.hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.clear')), findsNothing);

    await type('horizon');
    expect(find.byKey(const ValueKey('search.results')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.sectionMovies')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.hint')), findsNothing);
    expect(find.text('Horizon (2024)'), findsOneWidget);

    await type('veilleurs');
    expect(find.byKey(const ValueKey('search.sectionSeries')), findsOneWidget);

    await type('zzzzqx');
    expect(find.byKey(const ValueKey('search.none')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.results')), findsNothing);

    // La croix vide le champ et revient à l'invitation.
    await tester.tap(find.byKey(const ValueKey('search.clear')));
    await settle(tester);
    expect(find.byKey(const ValueKey('search.hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.clear')), findsNothing);
  });

  Future<void> typeQuery(
    WidgetTester tester,
    String text, {
    bool wait = true,
  }) async {
    // Sans attente : une roue de chargement tourne sans fin, `settle`
    // échouerait.
    Future<void> next() => wait ? settle(tester) : tester.pump();
    await tester.tap(find.byKey(const ValueKey('shell.tabSearch')));
    await next();
    await tester.enterText(find.byKey(const ValueKey('search.field')), text);
    // La recherche part 300 ms après la dernière frappe.
    await tester.pump(const Duration(milliseconds: 300));
    await next();
  }

  testWidgets('Recherche : listes en échec, erreur puis nouvel essai', (
    tester,
  ) async {
    var down = true;
    final routes = {
      '': activeAccountJson,
      'get_vod_categories': fixture('vod_categories'),
      'get_vod_streams': fixture('vod_streams'),
      'get_series_categories': fixture('series_categories'),
      'get_series': fixture('series'),
    };
    server = FakeAdapter((options) async {
      final action = options.uri.queryParameters['action'] ?? '';
      final body = routes[action];
      final listing = action == 'get_vod_streams' || action == 'get_series';
      return body == null || (down && listing)
          ? ResponseBody.fromString('', 500)
          : ResponseBody.fromString(body, 200);
    });
    await pumpApp(tester, openMovies: false);

    await typeQuery(tester, 'horizon');
    expect(find.byKey(const ValueKey('search.error')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.results')), findsNothing);

    down = false;
    await tester.tap(find.byKey(const ValueKey('catalog.errorRetry')));
    await settle(tester);
    expect(find.byKey(const ValueKey('search.error')), findsNothing);
    expect(find.byKey(const ValueKey('search.results')), findsOneWidget);
  });

  testWidgets('Recherche : chargement tant que les listes arrivent', (
    tester,
  ) async {
    final gate = Completer<void>();
    await pumpApp(
      tester,
      openMovies: false,
      waitForIndex: false,
      overrides: [
        catalogIndexProvider.overrideWith2((kind) => _GatedIndex(kind, gate)),
      ],
    );

    await typeQuery(tester, 'horizon', wait: false);
    expect(find.byKey(const ValueKey('search.loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.results')), findsNothing);

    gate.complete();
    await settle(tester);
    expect(find.byKey(const ValueKey('search.loading')), findsNothing);
    expect(find.byKey(const ValueKey('search.results')), findsOneWidget);
  });
}

/// Index qui ne se charge qu'à l'ouverture de [gate].
class _GatedIndex extends CatalogIndexNotifier {
  _GatedIndex(super.kind, this.gate);

  final Completer<void> gate;

  @override
  Future<Loaded<KindIndex>> build() async {
    await gate.future;
    return super.build();
  }
}
