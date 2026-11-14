import 'dart:io';

import 'package:couchplay/accounts/server_session.dart';
import 'package:couchplay/catalog/catalog_cache.dart';
import 'package:couchplay/catalog/catalog_providers.dart';
import 'package:couchplay/catalog/catalog_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_app.dart';
import '../support/settle.dart';

void main() {
  setUpCatalogApp();

  testWidgets('« Actualiser » : catégories et liste lues une fois chacune, '
      'sans décodage du cache jeté avant la requête', (tester) async {
    // Le dépôt lit l'horloge une fois par chargement quand un cache existe :
    // elle compte les chargements.
    var loads = 0;
    await pumpApp(
      tester,
      overrides: [
        catalogRepositoryProvider.overrideWith(
          (ref) => CatalogRepository(
            ref.watch(serverClientProvider)!,
            CatalogCache(
              Directory('${root.path}/accounts/compte/catalog'),
              serverKey: 'test',
            ),
            now: () {
              loads++;
              return DateTime.now();
            },
          ),
        ),
      ],
    );
    loads = 0;

    await tester.tap(find.byTooltip('Actualiser'));
    await settle(tester);

    expect(loads, 2);
  });
}
