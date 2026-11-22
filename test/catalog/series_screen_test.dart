import 'package:couchplay/catalog/series_screen.dart';
import 'package:couchplay/downloads/download.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/library/library.dart';
import 'package:couchplay/library/library_store.dart';
import 'package:couchplay/server/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_app.dart';
import '../support/fake_downloads.dart';
import '../support/settle.dart';

void main() {
  setUpCatalogApp();
  _failureReason();

  testWidgets('progression enregistrée (toutes les 10 s sous le lecteur) : '
      "seul l'épisode se refait, pas la fiche", (tester) async {
    await pumpApp(tester, openMovies: false);
    await tester.tap(find.byKey(const ValueKey('shell.tabSeries')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('catalog.poster.series-17')));
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

  testWidgets('titre de la fiche : le nom propre, sans les étiquettes', (
    tester,
  ) async {
    await pumpApp(tester, openMovies: false);
    Navigator.of(tester.element(find.byType(Scaffold).first)).push(
      MaterialPageRoute<void>(
        builder: (_) => const SeriesScreen(
          item: CatalogItem(
            kind: ContentKind.series,
            id: '1',
            name: 'FR - Les Veilleurs (2024) HD VF',
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Les Veilleurs (2024)'), findsOneWidget);
    expect(find.text('FR - Les Veilleurs (2024) HD VF'), findsNothing);
  });

  testWidgets(
    "épisode demandé dans une saison absente : la fiche reste en haut",
    (tester) async {
      await pumpApp(tester, size: const Size(400, 400));
      Navigator.of(tester.element(find.byType(Scaffold).first)).push(
        MaterialPageRoute<void>(
          builder: (_) => const SeriesScreen(
            item: CatalogItem(
              kind: ContentKind.series,
              id: '17',
              name: 'Série',
            ),
            episode: PlayItem.episode(
              id: 'absent',
              extension: 'mkv',
              name: 'Série',
              seriesId: '17',
              season: 7,
              episode: 1,
            ),
          ),
        ),
      );
      await settle(tester);
      // Assez d'images pour que l'ancien défilement (40 tentatives) soit fini.
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      expect(scrollable.position.pixels, 0);
    },
  );

  testWidgets('« Télécharger la saison » met en file ceux de la saison '
      'affichée, dans cet ordre ; chaque épisode a son bouton', (tester) async {
    final fake = FakeDownloads();
    await pumpApp(
      tester,
      openMovies: false,
      overrides: [downloadsProvider.overrideWith(() => fake)],
    );
    await tester.tap(find.byKey(const ValueKey('shell.tabSeries')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('catalog.poster.series-17')));
    await settle(tester);

    // Un bouton par épisode de la saison 1.
    expect(find.byTooltip('Télécharger'), findsNWidgets(3));
    await tester.tap(
      find.byKey(const ValueKey('catalog.episodeDownload.6913')),
    );
    await tester.pump();
    expect(fake.calls, ['add episode:6913']);

    fake.calls.clear();
    await tester.tap(find.byKey(const ValueKey('catalog.seasonDownload')));
    await tester.pump();
    expect(fake.calls, ['add episode:6912 episode:6913 episode:6914']);
  });

  testWidgets('saison entièrement téléchargée : bouton de saison grisé', (
    tester,
  ) async {
    PlayItem episode(String id, int number) => PlayItem.episode(
      id: id,
      extension: 'mkv',
      name: 'Les Veilleurs',
      seriesId: '17',
      season: 1,
      episode: number,
    );
    final items = [episode('6912', 1), episode('6913', 2), episode('6914', 3)];
    final fake = FakeDownloads({
      for (final item in items)
        item.key: download(item, DownloadStatus.ready, received: 1000),
    });
    await pumpApp(
      tester,
      openMovies: false,
      overrides: [downloadsProvider.overrideWith(() => fake)],
    );
    await tester.tap(find.byKey(const ValueKey('shell.tabSeries')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('catalog.poster.series-17')));
    await settle(tester);

    final button = tester.widget<OutlinedButton>(
      find.descendant(
        of: find.byKey(const ValueKey('catalog.seasonDownload')),
        matching: find.bySubtype<OutlinedButton>(),
      ),
    );
    expect(button.onPressed, isNull);
  });
}

void _failureReason() {
  testWidgets("épisode en échec : la raison s'affiche sous l'épisode, sans "
      'survol', (tester) async {
    const item = PlayItem.episode(
      id: '6912',
      extension: 'mkv',
      name: 'Les Veilleurs',
      seriesId: '17',
      season: 1,
      episode: 1,
    );
    final fake = FakeDownloads({
      item.key: download(
        item,
        DownloadStatus.failed,
        error: 'Espace disque insuffisant',
      ),
    });
    await pumpApp(
      tester,
      openMovies: false,
      overrides: [downloadsProvider.overrideWith(() => fake)],
    );
    await tester.tap(find.byKey(const ValueKey('shell.tabSeries')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('catalog.poster.series-17')));
    await settle(tester);

    final reason = find.byKey(const ValueKey('catalog.episodeError.6912'));
    expect(reason, findsOneWidget);
    expect(tester.widget<Text>(reason).data, 'Espace disque insuffisant');
    // Les autres épisodes n'en ont pas.
    expect(
      find.byKey(const ValueKey('catalog.episodeError.6913')),
      findsNothing,
    );
  });
}
