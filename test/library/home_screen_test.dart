import 'package:couchplay/catalog/poster_grid.dart';
import 'package:couchplay/downloads/download.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/library/home_screen.dart';
import 'package:couchplay/library/library.dart';
import 'package:couchplay/library/library_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_downloads.dart';
import '../support/library_container.dart';

void main() {
  testWidgets("sous le lecteur, la progression ne refait pas l'accueil ; "
      'il se met à jour au retour', (tester) async {
    final container = await libraryContainer(tester);
    final library = container.read(libraryProvider.notifier);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(navigatorKey: navigator, home: const HomeScreen()),
      ),
    );
    // Le lecteur, par-dessus l'accueil.
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pumpAndSettle();

    var builds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is HomeScreen) builds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    for (final minutes in [1, 2, 3]) {
      await tester.runAsync(
        () => library.saveProgress(
          const PlayItem.movie(id: '1', extension: 'mkv', name: 'Horizon'),
          position: Duration(minutes: minutes),
          duration: const Duration(minutes: 90),
        ),
      );
      await tester.pump();
    }
    expect(builds, 0);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Continuer à regarder'), findsOneWidget);
    expect(find.text('Horizon'), findsOneWidget);
  });

  testWidgets('« Ma liste » de 200 favoris : seules les affiches visibles '
      'sont construites, à la hauteur exacte de la rangée', (tester) async {
    final container = await libraryContainer(tester);
    final library = container.read(libraryProvider.notifier);
    await tester.runAsync(() async {
      for (var i = 0; i < 200; i++) {
        await library.addFavorite(
          key: 'movie:$i',
          // Un titre sur deux tient sur deux lignes.
          name: i.isEven ? 'Film $i' : 'Un très long titre de film numéro $i',
        );
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    final built = find.byType(PosterTile, skipOffstage: false).evaluate();
    expect(built.length, lessThan(20));
    // Pas de place perdue ni de débordement (qui ferait échouer le test) :
    // le plus haut titre finit à la marge du bas de sa case.
    double gapUnderTitle(Element tile) {
      RenderParagraph? title;
      void visit(Element e) {
        if (e.renderObject case final RenderParagraph p) title = p;
        e.visitChildren(visit);
      }

      tile.visitChildren(visit);
      final box = tile.renderObject! as RenderBox;
      final bottom = title!.localToGlobal(Offset(0, title!.size.height)).dy;
      return box.localToGlobal(Offset(0, box.size.height)).dy - bottom;
    }

    expect(built.map(gapUnderTitle).reduce((a, b) => a < b ? a : b), 8);
  });

  testWidgets('accueil : pastille « téléchargé » sur un contenu prêt', (
    tester,
  ) async {
    const ready = PlayItem.movie(id: '1', extension: 'mkv', name: 'Horizon');
    const other = PlayItem.movie(id: '2', extension: 'mkv', name: 'Dune');
    final container = await libraryContainer(
      tester,
      overrides: [
        downloadsProvider.overrideWith(
          () => FakeDownloads({
            ready.key: download(ready, DownloadStatus.ready),
            other.key: download(other, DownloadStatus.running),
          }),
        ),
      ],
    );
    final library = container.read(libraryProvider.notifier);
    await tester.runAsync(() async {
      for (final item in [ready, other]) {
        await library.saveProgress(
          item,
          position: const Duration(minutes: 10),
          duration: const Duration(minutes: 90),
        );
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();

    Finder badgeOf(PlayItem item) => find.descendant(
      of: find.byKey(ValueKey('library.continueTile.${item.key}')),
      matching: find.byIcon(Icons.download_done),
    );
    expect(badgeOf(ready), findsOneWidget);
    expect(badgeOf(other), findsNothing);
  });
}
