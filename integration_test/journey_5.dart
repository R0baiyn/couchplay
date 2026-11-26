// Parcours 5 de Docs/FEATURES.md : le direct, de l'onglet TV au zapping, aux
// favorites, au guide et à la recherche, puis un refus du serveur.
// Lancé par app_test.dart : flutter test integration_test -d windows.
// Un direct ne finit jamais : chaque lecteur ouvert est refermé par le test.
import 'dart:io';

import 'package:couchplay/live/guide_cell_view.dart';
import 'package:couchplay/logging.dart';
import 'package:couchplay/player/playback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'bench.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Nul si le démarrage a échoué : son erreur reste la seule affichée.
  FakeServer? server;
  setUpAll(() async => server = await FakeServer.start(live: true));
  tearDownAll(() async => server?.stop());

  testWidgets('parcours 5 : direct, zapping, favorites, guide, recherche', (
    tester,
  ) async {
    final app = await startIsolatedApp(tester);
    await addBenchAccount(tester, server!);
    int requests(int id) =>
        server!.requests('/live/$benchUser/$benchPassword/$id.ts');

    // 1. Onglet TV : le programme en cours d'une chaîne couverte par le
    // guide, rien sous une chaîne sans guide.
    await tester.tap(byKey('shell.tabLive'));
    await waitFor(
      tester,
      find.descendant(
        of: byKey('live.channel.9001'),
        matching: byKey('live.onAir.current'),
      ),
    );
    expect(byKey('live.channel.9003'), findsOneWidget);
    expect(
      find.descendant(
        of: byKey('live.channel.9003'),
        matching: byKey('live.onAir'),
      ),
      findsNothing,
    );

    // 2. La chaîne : l'image avance, aucune barre de temps (les barres sont
    // construites même masquées).
    await tester.tap(byKey('live.channel.9001'));
    await waitSettled(tester, byKey('live.player'));
    final player = app.container.read(playbackProvider).player;
    await _waitLive(tester, player, 9001);
    expect(byKey('player.back'), findsOneWidget);
    for (final key in [
      'player.elapsed',
      'player.progress',
      'player.duration',
    ]) {
      expect(byKey(key), findsNothing);
    }

    // 3. Deux appuis ↓ rapides : le 2e dès que le bandeau montre la chaîne
    // suivante. Une seule ouverture, celle de la dernière chaîne choisie.
    Finder banner(String label) => find.descendant(
      of: byKey('live.player.banner'),
      matching: find.text(label),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await waitFor(tester, banner('2 · Chaîne 2 HD'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await waitFor(tester, banner('3 · Chaîne 3 HD'));
    await _waitLive(tester, player, 9003);
    expect(requests(9002), 0, reason: 'la chaîne sautée a été ouverte');
    expect(requests(9003), 1);

    // 4. Un autre appareil prend la connexion du compte : le flux est coupé,
    // une reconnexion, l'image avance de nouveau.
    final other = await _openStream(server!, benchUser, 9001);
    other.close(force: true);
    await waitUntil(
      tester,
      () => requests(9003) == 2,
      what: 'le flux coupé est redemandé',
    );
    await _waitLive(tester, player, 9003);
    await flushJournal();
    var journal = journalFile!.readAsStringSync();
    expect(journal, contains('Direct : flux coupé, reconnexion dans 1 s'));
    expect(journal, isNot(contains(benchPassword)));

    // 5. Retour : le focus sur la chaîne regardée ; cœur, favorites, puis
    // les récentes.
    await _closePlayer(tester);
    await waitUntil(
      tester,
      () => _focused(byKey('live.channel.9003')),
      what: 'le focus sur la chaîne regardée',
    );
    await tester.tap(byKey('live.favorite.9003'));
    // Fenêtre du banc : large, catégories en panneau latéral.
    await waitFor(tester, byKey('live.categoryTile.favorites'));
    await tester.tap(byKey('live.categoryTile.favorites'));
    await waitUntil(
      tester,
      () => byKey('live.channel.9001').evaluate().isEmpty,
      what: 'la liste des favorites',
    );
    expect(byKey('live.channel.9003'), findsOneWidget);

    await tester.tap(byKey('live.categoryTile.recent'));
    await waitFor(tester, byKey('live.channel.9001'));
    expect(byKey('live.channel.9003'), findsOneWidget);
    expect(byKey('live.channel.9002'), findsNothing);

    // 6. Guide : ouvert sur maintenant, OK sur le programme en cours → le
    // lecteur de la chaîne, sans détail.
    await tester.tap(byKey('live.categoryTile.104'));
    // La 9002 n'est ni favorite ni récente : la catégorie est bien là.
    await waitFor(tester, byKey('live.channel.9002'));
    await tester.tap(byKey('live.guide.open'));
    await waitSettled(tester, byKey('live.guide'));
    final cell = byKeyPrefix('live.guide.9001.');
    await waitUntil(
      tester,
      () => _focused(cell),
      what: 'le focus sur un programme de la 1re chaîne',
    );
    expect(byKey('live.guide.nowLine'), findsOneWidget);
    final focused = tester
        .widgetList<GuideCell>(cell)
        .singleWhere((c) => _focused(find.byWidget(c)));
    expect(focused.slot.programme, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await waitSettled(tester, byKey('live.player'));
    expect(byKey('live.guide.detail'), findsNothing);
    await _waitLive(tester, player, 9001);
    await _closePlayer(tester);
    await settledPageBack(tester);

    // 7. Recherche : la section « Chaînes », la puce « TV », puis le lecteur.
    await waitFor(tester, byKey('shell.tabSearch'));
    await waitUntil(
      tester,
      () => byKey('live.guide').evaluate().isEmpty,
      what: 'la grille est fermée',
    );
    await tester.tap(byKey('shell.tabSearch'));
    await waitFor(tester, byKey('search.field'));
    await tester.enterText(byKey('search.field'), 'chaîne 3');
    await waitFor(tester, byKey('search.sectionChannels'));
    await tester.tap(byKey('search.filter.live'));
    await waitFor(tester, byKey('live.channel.9003'));
    expect(byKey('search.sectionMovies'), findsNothing);
    await tester.tap(byKey('live.channel.9003'));
    await waitSettled(tester, byKey('live.player'));
    await _waitLive(tester, player, 9003);
    await _closePlayer(tester);

    // Aucune adresse du direct en clair, ni le mot de passe.
    await flushJournal();
    journal = journalFile!.readAsStringSync();
    expect(journal, isNot(contains('/live/$benchUser/')));
    expect(journal, isNot(contains(benchPassword)));
    // Chaque chaîne quittée laisse sa ligne de fin de lecture (D-090).
    expect(journal, contains(RegExp(r'Fin de lecture : \d+ s, décodage ')));
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('parcours 5 : direct refusé, adresse masquée au journal', (
    tester,
  ) async {
    await startIsolatedApp(tester);
    // « plein » : le faux serveur refuse un 2e flux du compte.
    await addBenchAccount(tester, server!, user: 'plein');
    final other = await _openStream(server!, 'plein', 9001);
    addTearDown(() => other.close(force: true));

    await tester.tap(byKey('shell.tabLive'));
    await waitFor(tester, byKey('live.channel.9001'));
    await tester.tap(byKey('live.channel.9001'));
    await waitFor(tester, byKey('live.player.error'));
    expect(find.textContaining('un autre appareil'), findsOneWidget);

    await flushJournal();
    final journal = journalFile!.readAsStringSync();
    expect(journal, contains('/live/***/***/9001.ts'));
    expect(journal, isNot(contains('/live/plein/')));
    expect(journal, isNot(contains(benchPassword)));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// Le flux de la chaîne [id] est ouvert et son image avance de 2 s.
Future<void> _waitLive(WidgetTester tester, Player player, int id) async {
  bool failed() => byKey('live.player.error').evaluate().isNotEmpty;
  bool playing() {
    final playlist = player.state.playlist;
    return byKey('live.player.opening').evaluate().isEmpty &&
        playlist.medias.isNotEmpty &&
        playlist.medias[playlist.index].uri.endsWith('/$id.ts') &&
        player.state.position > Duration.zero;
  }

  await waitUntil(
    tester,
    () => failed() || playing(),
    what: 'le flux de la chaîne $id est ouvert',
  );
  final from = player.state.position;
  await waitUntil(
    tester,
    () =>
        failed() || player.state.position >= from + const Duration(seconds: 2),
    what: 'l\'image de la chaîne $id avance',
  );
  expect(byKey('live.player.error'), findsNothing);
}

/// Échap : le lecteur du direct rend la main.
Future<void> _closePlayer(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await waitUntil(
    tester,
    () => byKey('live.player').evaluate().isEmpty,
    what: 'le lecteur est fermé',
  );
}

/// Un autre appareil du compte : il ouvre le flux de la chaîne [id] et le
/// lit sans fin, jusqu'à la fermeture du client rendu.
Future<HttpClient> _openStream(FakeServer server, String user, int id) async {
  final client = HttpClient();
  final request = await client.getUrl(
    Uri.parse('${server.host}/live/$user/$benchPassword/$id.ts'),
  );
  final response = await request.close();
  expect(response.statusCode, HttpStatus.ok);
  // Fermé de force : la lecture finit en erreur, attendue.
  response.listen((_) {}, onError: (_) {});
  return client;
}

/// Le focus est sur un élément de [finder] ou à l'intérieur.
bool _focused(Finder finder) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return find
      .ancestor(
        of: find.byElementPredicate((element) => element == context),
        matching: finder,
        matchRoot: true,
      )
      .evaluate()
      .isNotEmpty;
}
