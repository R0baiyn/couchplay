// Parcours 2 de Docs/FEATURES.md : reprise d'une lecture commencée.
// Lancé par app_test.dart : flutter test integration_test -d windows.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'bench.dart';

/// mpv reprend sur l'image clé qui précède la position demandée : la mire en
/// a une par seconde, et l'affichage arrondit à la seconde. 2 s couvrent ces
/// deux arrondis (écart mesuré : 0 s) sans laisser passer une reprise à 0
/// (on part d'au moins 40 s).
const _tolerance = 2;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Nul si le démarrage a échoué : son erreur reste la seule affichée.
  FakeServer? server;
  setUpAll(() async => server = await FakeServer.start());
  tearDownAll(() async => server?.stop());

  testWidgets('parcours 2 : reprise depuis la fiche et depuis l\'Accueil', (
    tester,
  ) async {
    await startIsolatedApp(tester);
    await addBenchAccount(tester, server!);
    await openFirstMovie(tester);
    int elapsed() => shownSeconds(tester, 'player.elapsed');

    // 1. Lecture, puis sauts de 10 s jusqu'au-delà du seuil de reprise (30 s).
    await tester.tap(byKey('catalog.play'));
    await waitPlaying(tester);
    var mouse = await showPlayerControls(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(byKey('player.forward'));
      await tester.pump();
    }
    await waitUntil(
      tester,
      () => elapsed() >= 40,
      what: 'la position dépasse 40 s après les sauts',
    );

    // 2. Sortie : la position est enregistrée.
    var left = await _leavePlayer(tester, mouse, elapsed);
    await waitFor(tester, byKey('catalog.play'));

    // 5 (fiche). Dialogue de reprise, « Reprendre à m:ss » → la lecture
    // repart là, pas à 0.
    await tester.tap(byKey('catalog.play'));
    await waitFor(tester, byKey('player.resumeContinue'));
    expect(byKey('player.resumeRestart'), findsOneWidget);
    final label = tester
        .widget<Text>(
          find.descendant(
            of: byKey('player.resumeContinue'),
            matching: find.byType(Text),
          ),
        )
        .data!;
    final saved = _parse(label.replaceFirst('Reprendre à ', ''));
    expect(saved, inInclusiveRange(left - 1, left + 1), reason: label);
    await tester.tap(byKey('player.resumeContinue'));
    await waitPlaying(tester);
    expect(elapsed(), greaterThanOrEqualTo(saved - _tolerance));
    mouse = await showPlayerControls(tester);
    left = await _leavePlayer(tester, mouse, elapsed);
    await waitFor(tester, byKey('catalog.play'));

    // 6. Dialogue fermé sans choisir : on reste sur la fiche, aucun lecteur.
    await tester.tap(byKey('catalog.play'));
    await waitFor(tester, byKey('player.resumeContinue'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await runFor(tester, const Duration(seconds: 1));
    expect(byKey('player.resumeContinue'), findsNothing);
    expect(byKey('player.elapsed'), findsNothing);
    expect(byKey('catalog.play'), findsOneWidget);

    // 3-4. Accueil (la fiche couvre les onglets : on la quitte) :
    // « Continuer à regarder » reprend sans dialogue.
    await tester.pageBack();
    await waitFor(tester, byKey('shell.tabHome'));
    await tester.tap(byKey('shell.tabHome'));
    final tile = byKeyPrefix('library.continueTile.');
    await waitFor(tester, tile);
    await tester.tap(tile.first);
    await waitPlaying(tester);
    expect(byKey('player.resumeContinue'), findsNothing);
    expect(elapsed(), greaterThanOrEqualTo(left - _tolerance));
    mouse = await showPlayerControls(tester);
    await _leavePlayer(tester, mouse, elapsed);

    // 5 (fin). Retour à la fiche, « Recommencer » → la lecture part de 0.
    await openFirstMovie(tester);
    await tester.tap(byKey('catalog.play'));
    await waitFor(tester, byKey('player.resumeRestart'));
    await tester.tap(byKey('player.resumeRestart'));
    await waitPlaying(tester);
    expect(elapsed(), lessThan(10), reason: 'reprise au lieu de 0:00');
    mouse = await showPlayerControls(tester);
    await _leavePlayer(tester, mouse, elapsed);
    await waitFor(tester, byKey('catalog.play'));
  }, timeout: const Timeout(Duration(minutes: 4)));
}

/// Quitte le lecteur par `player.back` ; rend la position affichée juste
/// avant la sortie.
Future<int> _leavePlayer(
  WidgetTester tester,
  TestGesture mouse,
  int Function() elapsed,
) async {
  await mouse.moveBy(const Offset(1, 1));
  await tester.pump();
  final left = elapsed();
  await tester.tap(byKey('player.back'));
  await waitUntil(
    tester,
    () => byKey('player.elapsed').evaluate().isEmpty,
    what: 'le lecteur est fermé',
  );
  await mouse.removePointer();
  return left;
}

int _parse(String time) =>
    time.split(':').fold(0, (total, part) => total * 60 + int.parse(part));
