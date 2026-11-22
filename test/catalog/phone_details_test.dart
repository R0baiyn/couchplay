import 'dart:convert';

import 'package:couchplay/catalog/versions.dart';
import 'package:couchplay/catalog/catalog_providers.dart';
import 'package:couchplay/catalog/movie_screen.dart';
import 'package:couchplay/catalog/series_screen.dart';
import 'package:couchplay/downloads/download.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/library/library.dart';
import 'package:couchplay/server/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_app.dart';
import '../support/fake_downloads.dart';
import '../support/real_font.dart';
import '../support/settle.dart';

// Titres inventés, aux longueurs relevées dans les vraies données (S051).
const _movieName =
    'Les Gardiens du Phare : Chronique de la Terrible Tempête - Le Voyage '
    'des Trois Sœurs et La Promesse Retrouvée (FHD VOSTFR)';
const _seriesName =
    'LIGHT OF THE NORTH: I Will Guard the Quiet Valley Forever with My '
    'Friend and Map!';
const _episodeTitle =
    'Les Navigateurs - S04E14 - À cette heure incertaine du matin';
const _plot =
    'Au bout de la côte, un phare guide encore les bateaux perdus dans la '
    'brume. Trois sœurs reviennent au village pour tenir une promesse faite '
    "des années plus tôt, alors que la tempête approche et que l'ancien "
    "gardien refuse de quitter la tour. Chacune garde un secret qui pourrait "
    "tout changer, et le temps presse avant que la mer ne recouvre la route.";

const _phone = Size(360, 800);
const _desktop = Size(1280, 800);

const _phoneMargin = 16.0;

const _versions = CatalogEntry([
  CatalogItem(
    kind: ContentKind.movies,
    id: '121303',
    name: '$_movieName FHD MULTI',
    extension: 'mkv',
  ),
  CatalogItem(
    kind: ContentKind.movies,
    id: '121302',
    name: '$_movieName HD VFQ',
    extension: 'mkv',
  ),
]);

final _seriesJson = jsonEncode({
  'info': {'name': _seriesName, 'plot': _plot},
  'episodes': {
    '4': [
      {
        'id': '7014',
        'episode_num': 14,
        'title': _episodeTitle,
        'container_extension': 'mkv',
        'info': {'plot': _plot, 'duration_secs': 2520},
      },
      {
        'id': '7015',
        'episode_num': 15,
        'title': 'Le Retour',
        'container_extension': 'mkv',
        'info': {'plot': 'Court.', 'duration': '00:00:00'},
      },
    ],
  },
});

/// Titre de la barre du haut sur grand écran : celui de la version choisie.
final _movieTitle = _versions.versions.first.parsedName.display;

const _episode = PlayItem.episode(
  id: '7014',
  extension: 'mkv',
  name: _seriesName,
  seriesId: '4912',
  season: 4,
  episode: 14,
);

Future<void> _openMovie(WidgetTester tester, Size size) async {
  await pumpApp(
    tester,
    size: size,
    openMovies: false,
    overrides: [
      movieDetailsProvider.overrideWith(
        (ref, id) => Future.value(
          const MovieDetails(
            details: Details(
              name: _movieName,
              year: 2023,
              plot: _plot,
              director: 'Camille Martin',
              cast: 'Alice Durand, Bruno Petit, Chloé Leroy',
            ),
            extension: 'mkv',
          ),
        ),
      ),
    ],
  );
  Navigator.of(tester.element(find.byType(Scaffold).first)).push(
    MaterialPageRoute<void>(
      builder: (_) => const MovieScreen(entry: _versions),
    ),
  );
  await settle(tester);
}

Future<FakeDownloads> _openSeries(
  WidgetTester tester,
  Size size, [
  Map<String, Download> downloads = const {},
]) async {
  final fake = FakeDownloads(downloads);
  await pumpApp(
    tester,
    size: size,
    openMovies: false,
    overrides: [
      seriesDetailsProvider.overrideWith(
        (ref, id) => Future.value(parseSeriesDetails(_seriesJson)),
      ),
      downloadsProvider.overrideWith(() => fake),
    ],
  );
  Navigator.of(tester.element(find.byType(Scaffold).first)).push(
    MaterialPageRoute<void>(
      builder: (_) => const SeriesScreen(
        item: CatalogItem(
          kind: ContentKind.series,
          id: '4912',
          name: _seriesName,
        ),
      ),
    ),
  );
  await settle(tester);
  return fake;
}

RenderParagraph _paragraph(WidgetTester tester, Finder finder) =>
    tester.renderObject<RenderParagraph>(finder);

/// Nombre de lignes d'un texte affiché.
int _lines(WidgetTester tester, Finder finder) {
  final render = _paragraph(tester, finder);
  final line = render.getFullHeightForCaret(const TextPosition(offset: 0));
  return (render.size.height / line).round();
}

Finder _inAppBar(String text) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(text));

final _episodeTitleText = find.text('14. À cette heure incertaine du matin');

Finder _plotOf(String episodeId) => find.descendant(
  of: find.byKey(ValueKey('catalog.episodeCard.$episodeId')),
  matching: find.text(_plot),
);

void main() {
  setUpAll(loadRoboto);
  setUpCatalogApp();

  group('téléphone (360 × 800 dp)', () {
    testWidgets('fiche film (T-01, T-02, T-03) : résumé, réalisation et '
        'versions au bord gauche, versions sur une rangée, pas de titre en '
        'haut', (tester) async {
      await _openMovie(tester, _phone);
      expect(tester.takeException(), isNull);

      expect(tester.getTopLeft(find.text(_plot)).dx, _phoneMargin);
      expect(
        tester.getTopLeft(find.textContaining('Camille Martin')).dx,
        _phoneMargin,
      );
      final fhd = find.byKey(const ValueKey('catalog.versionChip.121303'));
      final hd = find.byKey(const ValueKey('catalog.versionChip.121302'));
      expect(tester.getTopLeft(fhd).dx, _phoneMargin);
      expect(tester.getTopLeft(hd).dy, tester.getTopLeft(fhd).dy);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('catalog.play'))).dx,
        _phoneMargin,
      );

      // Le titre entier est dans la fiche, pas coupé dans la barre du haut.
      expect(_inAppBar(_movieTitle), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      final title = find.text(_movieName);
      expect(title, findsOneWidget);
      expect(_paragraph(tester, title).didExceedMaxLines, isFalse);
    });

    testWidgets('fiche série (T-01, T-03) : résumé au bord gauche, pas de '
        'titre en haut, aucun débordement', (tester) async {
      await _openSeries(tester, _phone);
      expect(tester.takeException(), isNull);

      final header = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.text(_plot),
      );
      expect(tester.getTopLeft(header.first).dx, _phoneMargin);
      expect(_inAppBar(_seriesName), findsNothing);
      expect(find.text(_seriesName), findsOneWidget);
    });

    testWidgets("ligne d'épisode (T-04, T-06) : « N. Titre » sans préfixe ni "
        'coupure, durée dessous, résumé entier sur toute la largeur', (
      tester,
    ) async {
      await _openSeries(tester, _phone);
      final plot = _plotOf('7014');
      await tester.scrollUntilVisible(plot, 200);
      expect(tester.takeException(), isNull);

      // Titre lisible : quelques lignes, pas une colonne de 4 lettres.
      expect(_episodeTitleText, findsOneWidget);
      expect(_paragraph(tester, _episodeTitleText).maxLines, isNull);
      expect(_lines(tester, _episodeTitleText), lessThanOrEqualTo(3));

      final duration = find.text('42 min');
      expect(
        tester.getTopLeft(duration).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(_episodeTitleText).dy),
      );
      expect(
        tester.getTopLeft(duration).dx,
        tester.getTopLeft(_episodeTitleText).dx,
      );

      final render = _paragraph(tester, plot);
      expect(render.maxLines, isNull);
      expect(render.didExceedMaxLines, isFalse);
      // La carte sans sa marge extérieure.
      final card = find
          .descendant(
            of: find.byKey(const ValueKey('catalog.episodeCard.7014')),
            matching: find.byType(Material),
          )
          .first;
      // Résumé aussi large que la ligne (moins le retrait intérieur de 8).
      expect(render.constraints.maxWidth, tester.getSize(card).width - 16);
      expect(tester.getTopLeft(plot).dx, tester.getTopLeft(card).dx + 8);
      // Sous la vignette et le titre.
      expect(
        tester.getTopLeft(plot).dy,
        greaterThan(tester.getBottomLeft(duration).dy),
      );

      // Durée absente des données : pas de ligne vide.
      expect(find.text('0 min'), findsNothing);
    });

    testWidgets('menu ⋮ (T-04) : « Marquer comme vu » coche, « Télécharger » '
        'met en file', (tester) async {
      final fake = await _openSeries(tester, _phone);
      final menu = find.byKey(const ValueKey('catalog.episodeMenu.7014'));

      // Plus d'icône de téléchargement sur la ligne : elle est dans le menu.
      expect(
        find.byKey(const ValueKey('catalog.episodeDownload.7014')),
        findsNothing,
      );
      await tester.tap(menu);
      await settle(tester);
      expect(
        find.byKey(const ValueKey('catalog.episodeToggleWatched')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('catalog.episodeDownloadItem')),
      );
      await settle(tester);
      expect(fake.calls, ['add ${_episode.key}']);

      final card = find.byKey(const ValueKey('catalog.episodeCard.7014'));
      Finder check() =>
          find.descendant(of: card, matching: find.byIcon(Icons.check_circle));
      expect(check(), findsNothing);
      await tester.tap(menu);
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('catalog.episodeToggleWatched')),
      );
      await settle(tester);
      expect(check(), findsOneWidget);
    });

    testWidgets("état du téléchargement (T-05) : rien avant, une petite icône "
        'une fois lancé ; le menu dit où il en est', (tester) async {
      await _openSeries(tester, _phone, {
        _episode.key: download(_episode, DownloadStatus.paused, received: 500),
      });
      expect(
        find.byKey(const ValueKey('catalog.episodeStatus.7014')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('catalog.episodeStatus.7015')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('catalog.episodeMenu.7014')));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('catalog.episodeDownloadItem')),
          matching: find.text('En pause · 50 %'),
        ),
        findsOneWidget,
      );
    });

    testWidgets("échec (S056) : la raison reste sous l'épisode", (
      tester,
    ) async {
      await _openSeries(tester, _phone, {
        _episode.key: download(
          _episode,
          DownloadStatus.failed,
          error: 'Espace disque insuffisant',
        ),
      });
      final reason = find.byKey(const ValueKey('catalog.episodeError.7014'));
      await tester.scrollUntilVisible(reason, 200);
      expect(tester.widget<Text>(reason).data, 'Espace disque insuffisant');
      expect(
        tester.getTopLeft(reason).dy,
        greaterThan(tester.getBottomLeft(_plotOf('7014')).dy),
      );
    });
  });

  group('PC et tablette (1280 × 800) : inchangé', () {
    testWidgets('fiche film : titre en haut, affiche à gauche du texte', (
      tester,
    ) async {
      await _openMovie(tester, _desktop);
      expect(tester.takeException(), isNull);
      expect(_inAppBar(_movieTitle), findsOneWidget);
      // Le texte commence après l'affiche (24 + 160 + 24).
      expect(tester.getTopLeft(find.text(_plot)).dx, 208);
    });

    testWidgets("ligne d'épisode : icône de téléchargement sur la ligne, "
        'résumé sur 3 lignes', (tester) async {
      await _openSeries(tester, _desktop);
      expect(tester.takeException(), isNull);
      expect(_inAppBar(_seriesName), findsOneWidget);
      expect(
        find.byKey(const ValueKey('catalog.episodeDownload.7014')),
        findsOneWidget,
      );
      expect(_paragraph(tester, _plotOf('7014')).maxLines, 3);
      expect(
        find.byKey(const ValueKey('catalog.episodeStatus.7014')),
        findsNothing,
      );
    });
  });
}
