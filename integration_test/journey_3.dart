// Parcours 3 de Docs/FEATURES.md : téléchargement → lecture hors ligne.
// Lancé par app_test.dart : flutter test integration_test -d windows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'bench.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Nul si le démarrage a échoué, ou une fois arrêté par le parcours.
  FakeServer? server;
  setUpAll(() async => server = await FakeServer.start());
  tearDownAll(() async => server?.stop());

  testWidgets('parcours 3 : téléchargement, puis lecture serveur arrêté', (
    tester,
  ) async {
    await startIsolatedApp(tester);
    await addBenchAccount(tester, server!);
    await openFirstMovie(tester);

    // 1. Télécharger : le bouton passe par l'attente et le pourcentage
    // jusqu'à « Téléchargé » (mire de 45 Mo servie en local).
    await tester.tap(byKey('catalog.download'));
    final label = find.descendant(
      of: byKey('catalog.download'),
      matching: find.byType(Text),
    );
    await waitUntil(
      tester,
      () => tester.widget<Text>(label).data == 'Téléchargé',
      what: 'le film est téléchargé (« Téléchargé »)',
      timeout: const Duration(minutes: 2),
    );

    // 2-4. Hors ligne : la ligne est sous « Prêts ».
    await tester.pageBack();
    await waitFor(tester, byKey('shell.tabDownloads'));
    await tester.tap(byKey('shell.tabDownloads'));
    final open = byKeyPrefix('downloads.open.');
    await waitFor(tester, open);
    expect(byKeyPrefix('downloads.readyRow.'), findsOneWidget);
    expect(byKey('downloads.empty'), findsNothing);

    // 5. Serveur arrêté (processus fini, port fermé) : aucune requête ne
    // peut plus aboutir, la lecture ne peut venir que du fichier local.
    await server!.stop();
    server = null;
    await tester.tap(open.first);
    await waitPlaying(tester);
    int elapsed() => shownSeconds(tester, 'player.elapsed');
    final started = elapsed();
    await waitUntil(
      tester,
      () => elapsed() >= started + 2,
      what: 'la lecture locale avance encore de 2 s',
    );
    expect(byKey('player.error'), findsNothing);

    // 6 (début). Retour à l'écran des téléchargements.
    final mouse = await showPlayerControls(tester);
    await tester.tap(byKey('player.back'));
    await waitUntil(
      tester,
      () => byKey('player.elapsed').evaluate().isEmpty,
      what: 'le lecteur est fermé',
    );
    await mouse.removePointer();
    expect(open, findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
