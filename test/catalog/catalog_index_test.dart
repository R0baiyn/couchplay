import 'dart:async';
import 'dart:io';

import 'package:couchplay/accounts/server_session.dart';
import 'package:couchplay/catalog/catalog_cache.dart';
import 'package:couchplay/catalog/catalog_providers.dart';
import 'package:couchplay/catalog/catalog_repository.dart';
import 'package:couchplay/catalog/catalog_settings.dart';
import 'package:couchplay/catalog/catalog_settings_screen.dart';
import 'package:couchplay/home_shell.dart';
import 'package:couchplay/server/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_app.dart';
import '../support/settle.dart';

// Le dépôt lit l'horloge une fois par chargement quand un cache existe :
// elle compte les chargements.
var loads = 0;

Future<void> pumpCountingApp(WidgetTester tester) async {
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
}

void main() {
  setUpCatalogApp();

  testWidgets('« Actualiser » : catégories et liste lues une fois chacune, '
      'sans décodage du cache jeté avant la requête', (tester) async {
    await pumpCountingApp(tester);

    await tester.tap(find.byTooltip('Actualiser'));
    await settle(tester);

    expect(loads, 2);
  });

  testWidgets("une catégorie de films cochée ne refait pas l'index des "
      'séries', (tester) async {
    await pumpCountingApp(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeShell)),
    );
    const category = Category(id: '619', name: 'Films 4K');
    for (var i = 0; i < 5; i++) {
      // L'écriture des réglages est un vrai fichier : hors de l'horloge
      // factice.
      await tester.runAsync(
        () => container
            .read(catalogFilterProvider.notifier)
            .setCategory(ContentKind.movies, category, shown: i.isOdd),
      );
      await settle(tester);
    }
    // Un calcul de l'index des films par clic, aucun pour les séries.
    expect(loads, 5);
  });

  testWidgets("réglages ouverts : les clics sont regroupés, l'index se refait "
      'une fois au retour', (tester) async {
    await pumpCountingApp(tester);
    final shell = tester.element(find.byType(HomeShell));
    final container = ProviderScope.containerOf(shell);
    unawaited(
      Navigator.of(shell).push(
        MaterialPageRoute<void>(builder: (_) => const CatalogSettingsScreen()),
      ),
    );
    await settle(tester);
    const category = Category(id: '619', name: 'Films 4K');
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => container
            .read(catalogFilterProvider.notifier)
            .setCategory(ContentKind.movies, category, shown: i.isOdd),
      );
      await settle(tester);
    }
    expect(loads, 0, reason: 'accueil masqué : index en pause');

    Navigator.of(shell).pop();
    await settle(tester);
    expect(loads, 1);
  });
}
