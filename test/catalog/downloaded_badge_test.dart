import 'package:couchplay/catalog/poster_grid.dart';
import 'package:couchplay/catalog/versions.dart';
import 'package:couchplay/downloads/download.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/library/library.dart';
import 'package:couchplay/library/library_store.dart';
import 'package:couchplay/server/models.dart';
import 'package:couchplay/television.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_downloads.dart';

const _film = CatalogItem(kind: ContentKind.movies, id: '1', name: 'Mirage');
const _series = CatalogItem(
  kind: ContentKind.series,
  id: '7',
  name: 'Les Veilleurs',
);
const _episode = PlayItem.episode(
  id: '71',
  extension: 'mkv',
  name: 'Les Veilleurs',
  seriesId: '7',
  season: 1,
  episode: 1,
);

/// Pastille « téléchargé » d'une affiche de la grille.
Finder _badge(String posterId) => find.descendant(
  of: find.byKey(ValueKey('catalog.poster.$posterId')),
  matching: find.byKey(const ValueKey('catalog.badgeDownloaded')),
);

void main() {
  Future<FakeDownloads> pumpGrid(
    WidgetTester tester,
    List<Download> downloads, {
    bool television = false,
    double width = 400,
    Library library = const Library(),
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeDownloads({for (final d in downloads) d.key: d});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadsProvider.overrideWith(() => fake),
          libraryProvider.overrideWithBuild((_, _) => library),
          televisionProvider.overrideWithValue(television),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverPosterGrid(
                  entries: const [
                    CatalogEntry([_film]),
                    CatalogEntry([_series]),
                  ],
                  onOpen: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return fake;
  }

  testWidgets('film prêt et série avec un épisode prêt : pastille', (
    tester,
  ) async {
    await pumpGrid(tester, [
      download(movie, DownloadStatus.ready),
      download(_episode, DownloadStatus.ready),
    ]);
    expect(_badge('movies-1'), findsOneWidget);
    expect(_badge('series-7'), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.download_done).first).semanticLabel,
      'Téléchargé',
    );
  });

  for (final status in [
    DownloadStatus.queued,
    DownloadStatus.running,
    DownloadStatus.paused,
    DownloadStatus.failed,
  ]) {
    testWidgets('${status.name} : pas de pastille', (tester) async {
      await pumpGrid(tester, [
        download(movie, status),
        download(_episode, status),
      ]);
      expect(find.byIcon(Icons.download_done), findsNothing);
    });
  }

  testWidgets('vidéo supprimée : la pastille part', (tester) async {
    final fake = await pumpGrid(tester, [
      download(movie, DownloadStatus.ready),
    ]);
    expect(_badge('movies-1'), findsOneWidget);

    fake.state = const DownloadsState();
    await tester.pump();
    expect(find.byIcon(Icons.download_done), findsNothing);
  });

  testWidgets('Android TV : jamais de pastille', (tester) async {
    await pumpGrid(tester, [
      download(movie, DownloadStatus.ready),
      download(_episode, DownloadStatus.ready),
    ], television: true);
    expect(find.byIcon(Icons.download_done), findsNothing);
  });

  testWidgets('avancement d\'un téléchargement : aucune affiche ne se '
      'reconstruit', (tester) async {
    await pumpGrid(tester, [
      download(movie, DownloadStatus.ready),
      download(_episode, DownloadStatus.running),
    ]);
    final rebuilt = <String>[];
    debugOnRebuildDirtyWidget = (element, _) =>
        rebuilt.add(element.widget.runtimeType.toString());
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    ProviderScope.containerOf(tester.element(find.byType(SliverPosterGrid)))
        .read(downloadProgressProvider.notifier)
        .publish(const DownloadProgress('episode:71', 500, 1000));
    await tester.pump();
    debugOnRebuildDirtyWidget = null;
    expect(rebuilt, isNot(contains('PosterTile')));
    expect(rebuilt, isNot(contains('_EntryTile')));
  });

  testWidgets('plus petite tuile : cœur, coche et pastille tiennent', (
    tester,
  ) async {
    await pumpGrid(
      tester,
      [download(movie, DownloadStatus.ready)],
      // Deux colonnes sur l'écran le plus étroit.
      width: 280,
      library: Library(
        favorites: {
          'movie:1': Favorite(
            key: 'movie:1',
            name: 'Mirage',
            addedAt: DateTime.utc(2026),
          ),
        },
        progress: {
          'movie:1': Progress(
            item: movie,
            position: const Duration(minutes: 99),
            duration: const Duration(minutes: 100),
            watched: true,
            updatedAt: DateTime.utc(2026),
          ),
        },
      ),
    );
    expect(_badge('movies-1'), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog.badgeFavorite')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog.badgeWatched')), findsOneWidget);
    final tile = tester.getRect(
      find.ancestor(of: find.text('Mirage'), matching: find.byType(PosterTile)),
    );
    for (final icon in [Icons.check, Icons.favorite, Icons.download_done]) {
      final rect = tester.getRect(find.byIcon(icon));
      expect(
        tile.contains(rect.topLeft) && tile.contains(rect.bottomRight),
        isTrue,
        reason: '$icon',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
