import 'package:couchplay/downloads/download.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/downloads/downloads_screen.dart';
import 'package:couchplay/library/library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_downloads.dart';

PlayItem _episode(String id, int season, int number) => PlayItem.episode(
  id: id,
  extension: 'mkv',
  name: 'Les Veilleurs',
  seriesId: '17',
  season: season,
  episode: number,
  episodeTitle: 'Titre $number',
);

Future<FakeDownloads> pumpScreen(
  WidgetTester tester,
  List<Download> downloads, {
  bool mobileOnly = false,
  Size size = const Size(800, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = FakeDownloads({for (final d in downloads) d.key: d});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        downloadsProvider.overrideWith(() => fake),
        mobileOnlyNetworkProvider.overrideWith(
          (ref) => Stream.value(mobileOnly),
        ),
      ],
      child: const MaterialApp(home: DownloadsScreen()),
    ),
  );
  await tester.pump();
  return fake;
}

void main() {
  testWidgets('rien téléchargé : état vide, pas de « Tout supprimer »', (
    tester,
  ) async {
    await pumpScreen(tester, []);
    expect(find.text('Aucun téléchargement'), findsOneWidget);
    expect(find.text('Tout supprimer'), findsNothing);
  });

  testWidgets('en cours : avancement, pause, reprise ; place occupée', (
    tester,
  ) async {
    const second = PlayItem.movie(id: '2', extension: 'mkv', name: 'Dune');
    final fake = await pumpScreen(tester, [
      download(
        movie,
        DownloadStatus.running,
        size: 2000000000,
        received: 500000000,
      ),
      download(
        second,
        DownloadStatus.paused,
        size: 1000000000,
        received: 500000000,
      ),
    ]);

    expect(find.text('En cours et en attente'), findsOneWidget);
    expect(find.text('25 % · 2 Go'), findsOneWidget);
    expect(find.text('En pause · 50 % · 1 Go'), findsOneWidget);
    // Ce qui est déjà reçu compte dans la place prise.
    expect(find.text('Place occupée : 1 Go'), findsOneWidget);

    await tester.tap(find.byTooltip('Mettre en pause'));
    await tester.tap(find.byTooltip('Reprendre'));
    expect(fake.calls, ['pause movie:1', 'resume movie:2']);
  });

  testWidgets('annuler un téléchargement commencé demande confirmation', (
    tester,
  ) async {
    final fake = await pumpScreen(tester, [
      download(movie, DownloadStatus.running, received: 100),
    ]);
    await tester.tap(find.byTooltip('Annuler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);

    await tester.tap(find.byTooltip('Annuler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler le téléchargement'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['remove movie:1']);
  });

  testWidgets('annuler un téléchargement pas commencé : sans confirmation', (
    tester,
  ) async {
    final fake = await pumpScreen(tester, [
      download(movie, DownloadStatus.queued),
    ]);
    await tester.tap(find.byTooltip('Annuler'));
    await tester.pump();
    expect(fake.calls, ['remove movie:1']);
  });

  testWidgets('en échec : la raison et « Réessayer »', (tester) async {
    final fake = await pumpScreen(tester, [
      download(movie, DownloadStatus.failed, error: 'Serveur injoignable'),
    ]);
    expect(find.text('Serveur injoignable'), findsOneWidget);
    await tester.tap(find.byTooltip('Réessayer'));
    expect(fake.calls, ['resume movie:1']);
  });

  testWidgets('file qui attend le Wi-Fi : le message le dit', (tester) async {
    await pumpScreen(tester, [
      download(movie, DownloadStatus.queued),
    ], mobileOnly: true);
    await tester.pump();
    expect(find.textContaining('réseau Wi-Fi'), findsOneWidget);
  });

  testWidgets('pas de message Wi-Fi quand rien n\'attend', (tester) async {
    await pumpScreen(tester, [
      download(movie, DownloadStatus.ready, received: 1000),
    ], mobileOnly: true);
    await tester.pump();
    expect(find.textContaining('réseau Wi-Fi'), findsNothing);
  });

  testWidgets('prêts : épisodes regroupés par série, tailles affichées', (
    tester,
  ) async {
    await pumpScreen(tester, [
      download(_episode('22', 1, 2), DownloadStatus.ready, size: 400000000),
      download(movie, DownloadStatus.ready, size: 1500000000),
      download(_episode('21', 1, 1), DownloadStatus.ready, size: 350000000),
    ]);

    expect(find.text('Prêts'), findsOneWidget);
    expect(find.text('Les Veilleurs · 2 épisodes · 750 Mo'), findsOneWidget);
    expect(find.text('1,5 Go'), findsOneWidget);
    // Dans l'ordre des épisodes, pas celui des ajouts.
    expect(
      tester.getTopLeft(find.text('S1E1 · Titre 1')).dy,
      lessThan(tester.getTopLeft(find.text('S1E2 · Titre 2')).dy),
    );
    expect(find.text('Place occupée : 2,3 Go'), findsOneWidget);
  });

  testWidgets('supprimer une vidéo prête : après confirmation', (tester) async {
    final fake = await pumpScreen(tester, [
      download(movie, DownloadStatus.ready, size: 1000),
    ]);
    await tester.tap(find.byTooltip('Supprimer la vidéo'));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['remove movie:1']);
  });

  testWidgets('« Tout supprimer » : après confirmation', (tester) async {
    final fake = await pumpScreen(tester, [
      download(movie, DownloadStatus.ready, size: 1000),
      download(_episode('21', 1, 1), DownloadStatus.running),
    ]);
    await tester.tap(find.text('Tout supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Tout supprimer ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);

    await tester.tap(find.text('Tout supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tout supprimer'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['removeAll']);
  });

  testWidgets('écran étroit : rien ne déborde', (tester) async {
    await pumpScreen(tester, [
      download(movie, DownloadStatus.running, size: 1000, received: 100),
      download(
        _episode('21', 1, 1),
        DownloadStatus.failed,
        error: 'Espace disque insuffisant sur cet appareil',
      ),
      download(_episode('22', 1, 2), DownloadStatus.ready, size: 5000),
    ], size: const Size(320, 640));
    expect(tester.takeException(), isNull);
  });
}
