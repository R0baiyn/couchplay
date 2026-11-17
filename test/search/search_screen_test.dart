import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_app.dart';
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
}
