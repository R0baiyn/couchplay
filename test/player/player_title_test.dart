import 'package:couchplay/library/library.dart';
import 'package:couchplay/player/player_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_font.dart';

// Noms inventés, aux longueurs relevées dans les vraies données.
const _longSeries =
    'LIGHT OF THE NORTH: I Will Guard the Quiet Valley Forever with My '
    'Friend and Map!';

PlayItem _episode(String series, {String? title = 'Le Retour'}) =>
    PlayItem.episode(
      id: '7014',
      extension: 'mkv',
      name: series,
      seriesId: '4912',
      season: 1,
      episode: 5,
      episodeTitle: title,
    );

const _movie = PlayItem.movie(id: '1', extension: 'mkv', name: 'Horizon');

/// Le titre du lecteur dans une barre de [width] dp : celle du lecteur moins
/// le bouton Retour (48) et les infos techniques.
Future<void> _pump(WidgetTester tester, PlayItem item, double width) async {
  final (title, subtitle) = playerTitle(item, phone: true);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: PlayerTitle(title: title, subtitle: subtitle),
          ),
        ),
      ),
    ),
  );
}

List<String> _lines(WidgetTester tester) => [
  for (final p in tester.renderObjectList<RenderParagraph>(
    find.descendant(
      of: find.byType(PlayerTitle),
      matching: find.byType(RichText),
    ),
  ))
    p.text.toPlainText(),
];

void main() {
  setUpAll(loadRoboto);

  group('playerTitle', () {
    test('téléphone, épisode : série, puis « S1E5 · titre »', () {
      expect(playerTitle(_episode('Vikings'), phone: true), (
        'Vikings',
        'S1E5 · Le Retour',
      ));
      expect(playerTitle(_episode('Vikings', title: null), phone: true), (
        'Vikings',
        'S1E5',
      ));
    });

    test('film, ou ailleurs que sur téléphone : une seule partie', () {
      expect(playerTitle(_movie, phone: true), ('Horizon', null));
      expect(playerTitle(_episode('Vikings'), phone: false), (
        'Vikings · S1E5 · Le Retour',
        null,
      ));
    });
  });

  group('PlayerTitle (T-08)', () {
    // Téléphone en paysage dans le lecteur : 800 dp moins le bouton Retour.
    for (final width in [700.0, 300.0]) {
      testWidgets('${width.toInt()} dp, série au nom long : 2 lignes, '
          'série puis « S1E5 · titre »', (tester) async {
        await _pump(tester, _episode(_longSeries), width);
        expect(_lines(tester), [_longSeries, 'S1E5 · Le Retour']);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('700 dp, série au nom court : une seule ligne', (tester) async {
      await _pump(tester, _episode('Vikings'), 700);
      expect(_lines(tester), ['Vikings · S1E5 · Le Retour']);
      final line = tester.renderObject<RenderParagraph>(
        find.byKey(const ValueKey('player.title')),
      );
      expect(line.didExceedMaxLines, isFalse);
    });

    testWidgets('film : une ligne, coupée « … » si trop longue', (
      tester,
    ) async {
      await _pump(tester, _movie, 700);
      expect(_lines(tester), ['Horizon']);
    });
  });
}
