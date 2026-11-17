// Parcours 1 de Docs/FEATURES.md : compte → catalogue → fiche film → lecture.
// Lancement : flutter test integration_test -d windows (vraie fenêtre).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'bench.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FakeServer server;
  setUpAll(() async => server = await FakeServer.start());
  tearDownAll(() => server.stop());

  testWidgets('parcours 1 : compte, catalogue, fiche film, lecture, retour', (
    tester,
  ) async {
    await startIsolatedApp(tester);

    // 1-3. Sans compte : formulaire, puis l'Accueil.
    await waitFor(tester, byKey('accounts.name'));
    expect(find.text('Ajouter un compte'), findsOneWidget);
    await tester.enterText(byKey('accounts.name'), 'Salon');
    await tester.enterText(byKey('accounts.host'), server.host);
    await tester.enterText(byKey('accounts.username'), benchUser);
    await tester.enterText(byKey('accounts.password'), benchPassword);
    await tester.tap(byKey('accounts.submit'));
    // L'onglet choisi perd sa Key (icône choisie sans Key) : l'Accueil se
    // reconnaît aux autres onglets, le formulaire fermé.
    await waitFor(tester, byKey('shell.tabMovies'));
    expect(byKey('accounts.submit'), findsNothing);

    // 4. Films : une catégorie, puis ses affiches.
    await tester.tap(byKey('shell.tabMovies'));
    final tiles = byKeyPrefix('catalog.categoryTile.');
    final picker = byKey('catalog.categoryPicker');
    await waitUntil(
      tester,
      () => tiles.evaluate().isNotEmpty || picker.evaluate().isNotEmpty,
      what: 'liste des catégories de films',
    );
    if (tiles.evaluate().isNotEmpty) {
      await tester.tap(tiles.first);
    } else {
      await tester.tap(picker);
      final sheetTile = byKeyPrefix('catalog.categorySheetTile.');
      await waitFor(tester, sheetTile);
      await tester.tap(sheetTile.first);
    }
    final posters = byKeyPrefix('catalog.poster.movies-');
    await waitFor(tester, posters);

    // 5. Fiche du film.
    await tester.tap(posters.first);
    await waitFor(tester, byKey('catalog.play'));
    expect(byKey('catalog.favorite'), findsOneWidget);
    expect(byKey('catalog.download'), findsOneWidget);

    // 6. Lecture : la position avance, la durée est connue.
    await tester.tap(byKey('catalog.play'));
    await waitFor(tester, byKey('player.elapsed'));
    int elapsed() => _seconds(tester, 'player.elapsed');
    await waitUntil(
      tester,
      () => elapsed() > 0 || byKey('player.error').evaluate().isNotEmpty,
      what: 'la lecture avance',
    );
    expect(byKey('player.error'), findsNothing);
    expect(_seconds(tester, 'player.duration'), greaterThan(0));
    final started = elapsed();
    await waitUntil(
      tester,
      () => elapsed() >= started + 2,
      what: 'la position avance encore de 2 s',
    );

    // 7. Pause : la position ne bouge plus ; reprise : elle repart.
    final mouse = await _showControls(tester);
    await tester.tap(byKey('player.playPause'));
    await runFor(tester, const Duration(milliseconds: 500));
    final paused = elapsed();
    await runFor(tester, const Duration(seconds: 2));
    expect(elapsed(), paused, reason: 'la position bouge en pause');
    await tester.tap(byKey('player.playPause'));
    await waitUntil(
      tester,
      () => elapsed() > paused,
      what: 'la lecture repart',
    );

    // 8. Retour à la fiche.
    await mouse.moveBy(const Offset(1, 1));
    await tester.pump();
    await tester.tap(byKey('player.back'));
    await waitFor(tester, byKey('catalog.play'));
    await waitUntil(
      tester,
      () => byKey('player.elapsed').evaluate().isEmpty,
      what: 'le lecteur est fermé',
    );
    await mouse.removePointer();
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Secondes affichées par le texte `m:ss` ou `h:mm:ss` de la Key [key].
int _seconds(WidgetTester tester, String key) {
  final text = tester.widget<Text>(byKey(key)).data!;
  return text.split(':').fold(0, (total, part) => total * 60 + int.parse(part));
}

/// Les contrôles du lecteur se masquent seuls pendant la lecture : la souris
/// sur l'image les réaffiche (survol), sans les basculer comme un clic.
Future<TestGesture> _showControls(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: tester.getCenter(byKey('player.video')));
  await mouse.moveBy(const Offset(1, 1));
  await tester.pump();
  return mouse;
}
