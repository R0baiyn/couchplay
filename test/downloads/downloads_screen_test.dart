import 'dart:io';

import 'package:couchplay/app.dart';
import 'package:couchplay/downloads/download.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/downloads/downloads_screen.dart';
import 'package:couchplay/downloads/export.dart';
import 'package:couchplay/focus_ring.dart';
import 'package:couchplay/library/library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_downloads.dart';
import '../support/real_font.dart';
import '../support/settle.dart';

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
  bool desktop = false,
  List<Override> overrides = const [],
  FakeDownloads? downloadsFake,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake =
      downloadsFake ?? FakeDownloads({for (final d in downloads) d.key: d});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        downloadsProvider.overrideWith(() => fake),
        desktopFilesProvider.overrideWithValue(desktop),
        ...overrides,
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

  testWidgets('place occupée : suit l’avancement en direct', (tester) async {
    await pumpScreen(tester, [
      download(
        movie,
        DownloadStatus.running,
        size: 2000000000,
        received: 500000000,
      ),
    ]);
    expect(find.text('Place occupée : 500 Mo'), findsOneWidget);

    ProviderScope.containerOf(tester.element(find.byType(DownloadsScreen)))
        .read(downloadProgressProvider.notifier)
        .publish(const DownloadProgress('movie:1', 900000000, 2000000000));
    await tester.pump();

    expect(find.text('Place occupée : 900 Mo'), findsOneWidget);
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

  group('ouvrir le dossier', () {
    testWidgets('PC : le bouton ouvre le dossier des vidéos du compte', (
      tester,
    ) async {
      final opened = <String>[];
      final fake = FakeDownloads()..videos = Directory('/vidéos/compte');
      await pumpScreen(
        tester,
        [],
        desktop: true,
        downloadsFake: fake,
        overrides: [
          openFolderProvider.overrideWithValue((d) async => opened.add(d.path)),
        ],
      );
      await tester.tap(find.byTooltip('Ouvrir le dossier des vidéos'));
      await tester.pump();
      expect(opened, [Directory('/vidéos/compte').path]);
    });

    testWidgets("l'explorateur introuvable : un message, pas de plantage", (
      tester,
    ) async {
      final fake = FakeDownloads()..videos = Directory('/vidéos/compte');
      await pumpScreen(
        tester,
        [],
        desktop: true,
        downloadsFake: fake,
        overrides: [
          openFolderProvider.overrideWithValue(
            (_) async => throw const ProcessException('xdg-open', []),
          ),
        ],
      );
      await tester.tap(find.byTooltip('Ouvrir le dossier des vidéos'));
      await tester.pump();
      expect(find.text("Impossible d'ouvrir le dossier."), findsOneWidget);
    });

    testWidgets('Android et Android TV : pas de bouton', (tester) async {
      await pumpScreen(tester, [download(movie, DownloadStatus.ready)]);
      expect(find.byTooltip('Ouvrir le dossier des vidéos'), findsNothing);
    });
  });

  group('exporter', () {
    late Directory root;
    late Directory target;
    late FakeDownloads fake;

    setUp(() {
      root = Directory.systemTemp.createTempSync('export_screen');
      target = Directory('${root.path}/choisi')..createSync();
      fake = FakeDownloads({
        movie.key: download(movie, DownloadStatus.ready, size: 5),
      });
      fake.files[movie.key] = File('${root.path}/movie-1.mkv')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<void> pump(
      WidgetTester tester, {
      String? picked,
      bool desktop = true,
    }) => pumpScreen(
      tester,
      [],
      desktop: desktop,
      downloadsFake: fake,
      overrides: [pickFolderProvider.overrideWithValue(() async => picked)],
    );

    testWidgets('copie sous le vrai titre, puis le dit', (tester) async {
      await pump(tester, picked: target.path);
      await tester.tap(find.byTooltip('Exporter la vidéo'));
      await settle(tester);
      expect(File('${target.path}/Mirage.mkv').readAsBytesSync(), [
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(find.text('Exporté dans ${target.path}'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.save_alt))
            .onPressed,
        isNotNull,
      );
      expect(find.textContaining('Export en cours'), findsNothing);
    });

    testWidgets('pendant la copie : la ligne le montre, l\'action est grisée', (
      tester,
    ) async {
      await pump(tester, picked: target.path);
      await tester.tap(find.byTooltip('Exporter la vidéo'));
      await tester.pump();
      expect(find.textContaining('Export en cours'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.save_alt))
            .onPressed,
        isNull,
      );
      await settle(tester);
      expect(find.textContaining('Export en cours'), findsNothing);
    });

    testWidgets('choix du dossier annulé : rien n\'est copié ni dit', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Exporter la vidéo'));
      await settle(tester);
      expect(target.listSync(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('fichier déjà là : jamais écrasé', (tester) async {
      File('${target.path}/Mirage.mkv').writeAsStringSync('à moi');
      await pump(tester, picked: target.path);
      await tester.tap(find.byTooltip('Exporter la vidéo'));
      await settle(tester);
      expect(File('${target.path}/Mirage.mkv').readAsStringSync(), 'à moi');
      expect(File('${target.path}/Mirage (2).mkv').readAsBytesSync(), [
        1,
        2,
        3,
        4,
        5,
      ]);
    });

    testWidgets('vidéo effacée entre-temps : l\'erreur est dite', (
      tester,
    ) async {
      await pump(tester, picked: target.path);
      fake.files.clear();
      await tester.tap(find.byTooltip('Exporter la vidéo'));
      await settle(tester);
      expect(find.text('La vidéo n\'existe plus.'), findsOneWidget);
      expect(target.listSync(), isEmpty);
    });

    testWidgets('erreur de copie : message clair, aucun fichier', (
      tester,
    ) async {
      fake.files[movie.key]!.deleteSync();
      await pump(tester, picked: target.path);
      await tester.tap(find.byTooltip('Exporter la vidéo'));
      await settle(tester);
      expect(find.text('La vidéo n\'existe plus.'), findsOneWidget);
      expect(target.listSync(), isEmpty);
    });

    testWidgets('Android et Android TV : pas d\'action d\'export', (
      tester,
    ) async {
      await pump(tester, desktop: false);
      expect(find.byTooltip('Exporter la vidéo'), findsNothing);
      expect(find.byTooltip('Supprimer la vidéo'), findsOneWidget);
    });
  });

  group('clavier et largeur minimale', () {
    late Directory root;
    late FakeDownloads fake;
    final opened = <String>[];

    setUp(() {
      opened.clear();
      root = Directory.systemTemp.createTempSync('export_keys');
      fake = FakeDownloads({
        movie.key: download(movie, DownloadStatus.ready, size: 5),
      })..videos = Directory('${root.path}/vidéos');
      fake.files[movie.key] = File('${root.path}/movie-1.mkv')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<void> pumpKeyboardApp(WidgetTester tester, {Size? size}) async {
      tester.view.physicalSize = size ?? const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            downloadsProvider.overrideWith(() => fake),
            mobileOnlyNetworkProvider.overrideWith(
              (ref) => Stream.value(false),
            ),
            desktopFilesProvider.overrideWithValue(true),
            openFolderProvider.overrideWithValue(
              (d) async => opened.add(d.path),
            ),
            pickFolderProvider.overrideWithValue(
              () async => '${root.path}/choisi',
            ),
          ],
          child: const CouchPlayApp(home: DownloadsScreen()),
        ),
      );
      await tester.pump();
    }

    /// Le contour que le bouton dessine.
    BorderSide sideOf(WidgetTester tester, Finder button) {
      final material = tester.widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first,
      );
      return (material.shape! as OutlinedBorder).side;
    }

    /// Tab jusqu'à ce que [button] ait le focus.
    Future<void> tabTo(WidgetTester tester, Finder button) async {
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<IconButton>();
        if (focused != null && focused == tester.widget(button)) return;
      }
      fail('le focus n\'atteint jamais le bouton');
    }

    testWidgets('ouvrir le dossier : anneau de focus, Entrée agit', (
      tester,
    ) async {
      await pumpKeyboardApp(tester);
      final button = find.widgetWithIcon(
        IconButton,
        Icons.folder_open_outlined,
      );
      expect(sideOf(tester, button), BorderSide.none);
      await tabTo(tester, button);
      await tester.pumpAndSettle();
      expect(sideOf(tester, button), focusRing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(opened, [fake.videos!.path]);
    });

    testWidgets('exporter : anneau de focus, Entrée agit', (tester) async {
      await pumpKeyboardApp(tester);
      final button = find.widgetWithIcon(IconButton, Icons.save_alt);
      expect(sideOf(tester, button), BorderSide.none);
      await tabTo(tester, button);
      await tester.pumpAndSettle();
      expect(sideOf(tester, button), focusRing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      // L'export est parti : l'action se grise, la ligne le dit.
      expect(find.textContaining('Export en cours'), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
    });

    testWidgets('« Tout supprimer » en icône : anneau de focus, Entrée agit', (
      tester,
    ) async {
      await pumpKeyboardApp(tester, size: const Size(360, 740));
      final button = find.widgetWithIcon(
        IconButton,
        Icons.delete_sweep_outlined,
      );
      expect(sideOf(tester, button), BorderSide.none);
      await tabTo(tester, button);
      await tester.pumpAndSettle();
      expect(sideOf(tester, button), focusRing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Tout supprimer ?'), findsOneWidget);
    });

    testWidgets('320 dp : ligne « Prêts » avec export, rien ne déborde', (
      tester,
    ) async {
      const long = PlayItem.movie(
        id: '9',
        extension: 'mkv',
        name: 'Un titre de film vraiment très très long qui doit passer à la ligne',
      );
      fake = FakeDownloads({
        movie.key: download(movie, DownloadStatus.ready, size: 5),
        long.key: download(long, DownloadStatus.ready, size: 5000000000),
        _episode('22', 1, 2).key: download(
          _episode('22', 1, 2),
          DownloadStatus.ready,
        ),
      })..videos = Directory('${root.path}/vidéos');
      await pumpKeyboardApp(tester, size: const Size(320, 640));
      expect(find.byTooltip('Exporter la vidéo'), findsNWidgets(3));
      expect(find.byTooltip('Ouvrir le dossier des vidéos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('écran étroit : titre entier', () {
    // Vraies largeurs de lettres : sous Ahem le titre ne tient jamais.
    setUpAll(loadRoboto);

    for (final desktop in [false, true]) {
      testWidgets('360 dp${desktop ? ' (fenêtre PC étroite)' : ''} : '
          '« Téléchargements » n\'est pas tronqué', (tester) async {
        await pumpScreen(
          tester,
          [download(movie, DownloadStatus.ready, size: 5000)],
          size: const Size(360, 740),
          desktop: desktop,
        );
        final title = tester.renderObject<RenderParagraph>(
          find.text('Téléchargements'),
        );
        expect(title.didExceedMaxLines, isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('« Tout supprimer » en icône : infobulle, confirmation', (
      tester,
    ) async {
      final fake = await pumpScreen(tester, [
        download(movie, DownloadStatus.ready),
      ], size: const Size(360, 740));
      expect(find.text('Tout supprimer'), findsNothing);
      await tester.tap(find.byTooltip('Tout supprimer'));
      await tester.pumpAndSettle();
      expect(find.text('Tout supprimer ?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Tout supprimer'));
      await tester.pumpAndSettle();
      expect(fake.calls, ['removeAll']);
    });

    testWidgets('grand écran : « Tout supprimer » reste un bouton texte', (
      tester,
    ) async {
      await pumpScreen(tester, [download(movie, DownloadStatus.ready)]);
      expect(find.widgetWithText(TextButton, 'Tout supprimer'), findsOneWidget);
    });
  });
}
