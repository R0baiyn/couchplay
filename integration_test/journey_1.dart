// Parcours 1 de Docs/FEATURES.md : compte → catalogue → fiche film → lecture.
// Lancé par app_test.dart : flutter test integration_test -d windows.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'bench.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Nul si le démarrage a échoué : son erreur reste la seule affichée.
  FakeServer? server;
  setUpAll(() async => server = await FakeServer.start());
  tearDownAll(() async => server?.stop());

  testWidgets('parcours 1 : compte, catalogue, fiche film, lecture, retour', (
    tester,
  ) async {
    await startIsolatedApp(tester);

    // 1-3. Sans compte : formulaire, puis l'Accueil.
    await addBenchAccount(tester, server!);

    // 4-5. Films : une catégorie, ses affiches, puis la fiche du film.
    await openFirstMovie(tester);
    expect(byKey('catalog.favorite'), findsOneWidget);
    expect(byKey('catalog.download'), findsOneWidget);

    // 6. Lecture : la position avance, la durée est connue.
    await tester.tap(byKey('catalog.play'));
    await waitPlaying(tester);
    int elapsed() => shownSeconds(tester, 'player.elapsed');
    expect(shownSeconds(tester, 'player.duration'), greaterThan(0));
    final started = elapsed();
    await waitUntil(
      tester,
      () => elapsed() >= started + 2,
      what: 'la position avance encore de 2 s',
    );

    // 7. Pause : la position ne bouge plus ; reprise : elle repart.
    final mouse = await showPlayerControls(tester);
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
