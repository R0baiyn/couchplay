import 'package:couchplay/catalog/series_screen.dart';
import 'package:couchplay/library/library.dart';
import 'package:couchplay/library/library_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_app.dart';
import '../support/settle.dart';

void main() {
  setUpCatalogApp();

  testWidgets('progression enregistrée (toutes les 10 s sous le lecteur) : '
      "seul l'épisode se refait, pas la fiche", (tester) async {
    await pumpApp(tester, openMovies: false);
    await tester.tap(find.text('Séries'));
    await settle(tester);
    await tester.tap(find.text('Les Veilleurs'));
    await settle(tester);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    var screenBuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is SeriesScreen) screenBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SeriesScreen)),
    );
    for (final minutes in [1, 2, 3]) {
      await tester.runAsync(
        () => container
            .read(libraryProvider.notifier)
            .saveProgress(
              const PlayItem.episode(
                id: '6912',
                extension: 'mkv',
                name: 'Les Veilleurs',
                seriesId: '17',
                season: 1,
                episode: 1,
              ),
              position: Duration(minutes: minutes),
              duration: const Duration(minutes: 40),
            ),
      );
      await tester.pump();
    }

    expect(screenBuilds, 0);
    // L'épisode, lui, montre où on en est.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
