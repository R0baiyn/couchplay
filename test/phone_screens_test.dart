import 'dart:convert';
import 'dart:io';

import 'package:couchplay/accounts/login_screen.dart';
import 'package:couchplay/app.dart';
import 'package:couchplay/poster_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/catalog_app.dart';
import 'support/real_font.dart';
import 'support/settle.dart';

// Téléphone en portrait (D-061) : chaque écran de l'inventaire à 360 × 800
// dp, police réelle, sans débordement. Les fiches, Hors ligne et le lecteur
// ont leurs propres juges (`phone_details_test`, `downloads_screen_test`,
// `player_title_test`).
const _phone = Size(360, 800);

/// La page qui défile de haut en bas (pas une rangée d'affiches).
final _vertical = find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .first;

const _longMovie =
    'Les Gardiens du Phare : Chronique de la Terrible Tempête - Le Voyage '
    'des Trois Sœurs et La Promesse Retrouvée (FHD VOSTFR)';
const _longSeries =
    'LIGHT OF THE NORTH: I Will Guard the Quiet Valley Forever with My '
    'Friend and Map!';

void main() {
  setUpCatalogApp();
  setUpAll(loadRoboto);

  /// Rien n'a débordé ni levé depuis le dernier contrôle.
  void clean(WidgetTester tester, String screen) =>
      expect(tester.takeException(), isNull, reason: screen);

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)).first);
    await settle(tester);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.pageBack();
    await settle(tester);
  }

  testWidgets('onglets, catégories, recherche, Ma liste, historique', (
    tester,
  ) async {
    // Un film et un épisode commencés, un favori : titres aux longueurs des
    // vraies données (`Docs/TELEPHONE.md`).
    File('${root.path}/accounts/compte/library.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'favorites': {
            'movie:94522': {'name': _longMovie, 'addedAt': 1700000000},
          },
          'progress': {
            'movie:94522': {
              'name': _longMovie,
              'extension': 'mkv',
              'position': 754,
              'duration': 6600,
              'updatedAt': '2026-01-01T00:00:00Z',
            },
            'episode:7014': {
              'name': _longSeries,
              'extension': 'mkv',
              'seriesId': '4912',
              'season': 4,
              'episode': 14,
              'title': 'À cette heure incertaine avant le matin',
              'position': 754,
              'duration': 2520,
              'updatedAt': '2026-01-02T00:00:00Z',
            },
          },
        }),
      );
    await pumpApp(tester, size: _phone, openMovies: false);
    clean(tester, 'Accueil');

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('library.favoritesAll')),
      200,
      scrollable: _vertical,
    );
    await tap(tester, 'library.favoritesAll');
    clean(tester, 'Ma liste');
    await back(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('library.historyButton')),
      200,
      scrollable: _vertical,
    );
    await tap(tester, 'library.historyButton');
    clean(tester, 'Historique');
    await back(tester);

    await tap(tester, 'shell.tabMovies');
    clean(tester, 'Films');
    await tap(tester, 'catalog.categoryPicker');
    clean(tester, 'panneau des catégories');
    await tester.tapAt(const Offset(180, 40));
    await settle(tester);

    await tap(tester, 'shell.tabSeries');
    clean(tester, 'Séries');

    await tap(tester, 'shell.tabSearch');
    clean(tester, 'Recherche vide');
    await tester.enterText(find.byKey(const ValueKey('search.field')), 'a');
    await settle(tester);
    clean(tester, 'Recherche, résultats');
    await tester.enterText(
      find.byKey(const ValueKey('search.field')),
      'zzzzzz',
    );
    await settle(tester);
    clean(tester, 'Recherche, aucun résultat');

    await tap(tester, 'shell.tabDownloads');
    clean(tester, 'Hors ligne');
  });

  testWidgets('réglages et leurs écrans', (tester) async {
    await pumpApp(tester, size: _phone, openMovies: false);
    await tap(tester, 'settings.open');
    clean(tester, 'Réglages');
    for (final key in [
      'settings.advanced',
      'settings.accounts',
      'settings.status',
      'settings.catalog',
    ]) {
      await tester.scrollUntilVisible(find.byKey(ValueKey(key)), 100);
      await tap(tester, key);
      clean(tester, key);
      if (key == 'settings.advanced') {
        await tap(tester, 'settings.journal');
        clean(tester, 'settings.journal');
        await back(tester);
      }
      if (key == 'settings.accounts') {
        await tap(tester, 'accounts.add');
        clean(tester, 'formulaire de compte');
        await back(tester);
      }
      await back(tester);
    }
  });

  testWidgets('connexion', (tester) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: CouchPlayApp(home: LoginScreen())),
    );
    await settle(tester);
    clean(tester, 'connexion');
  });

  testWidgets('T-09 : titre sous l\'affiche, 2 lignes puis « … » (inchangé)', (
    tester,
  ) async {
    // Grille de 2 colonnes à 360 dp.
    const title =
        'One Piece : Épisode du Phare : Le Lien Entre Les 3 Sœurs - Les '
        'Retrouvailles Miraculeuses et La Volonté Héritée (FHD VOSTFR)';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 164,
            child: PosterTile(title: title, imageUrl: null, onTap: () {}),
          ),
        ),
      ),
    );
    final text = tester.renderObject<RenderParagraph>(find.text(title));
    expect(text.maxLines, 2);
    expect(text.didExceedMaxLines, isTrue);
    clean(tester, 'affiche');
  });
}
