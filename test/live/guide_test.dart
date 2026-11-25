import 'dart:convert';

import 'package:couchplay/live/guide.dart';
import 'package:flutter_test/flutter_test.dart';

import '../json_generators.dart';

/// Midi UTC, 13 h à Paris.
final _now = DateTime.utc(2026, 11, 24, 12);

/// Guide minimal autour de [body], avec l'en-tête du vrai serveur.
String _xml(String body) =>
    '<?xml version="1.0" encoding="utf-8" ?>\n'
    '<!DOCTYPE tv SYSTEM "xmltv.dtd">\n'
    '<tv generator-info-name="test">$body</tv>';

String _programme(
  String start,
  String? stop,
  String title, {
  String channel = 'a.fr',
  String extra = '',
}) =>
    '<programme start="$start"${stop == null ? '' : ' stop="$stop"'} '
    'channel="$channel"><title>$title</title>$extra</programme>';

/// Lit [xml] par morceaux de [chunk] octets : un caractère accentué ou une
/// balise peut être coupé entre deux morceaux, comme sur le réseau.
Future<Guide> _read(
  String xml, {
  Set<String> channels = const {'a.fr', 'b.fr'},
  int chunk = 7,
}) {
  final bytes = utf8.encode(xml);
  return readGuide(
    Stream.fromIterable([
      for (var i = 0; i < bytes.length; i += chunk)
        bytes.sublist(i, (i + chunk).clamp(0, bytes.length)),
    ]),
    channels: channels,
    now: _now,
  );
}

List<String> _titles(Guide guide, [String channel = 'a.fr']) => [
  for (final p in guide.programmes[channel] ?? const <Programme>[]) p.title,
];

void main() {
  group('dates', () {
    test('décalage horaire converti en UTC', () {
      expect(
        parseGuideDate('20261124135000 +0100'),
        DateTime.utc(2026, 11, 24, 12, 50),
      );
      expect(
        parseGuideDate('20260701135000 +0200'),
        DateTime.utc(2026, 7, 1, 11, 50),
      );
      expect(
        parseGuideDate('20261124235000 -0500'),
        DateTime.utc(2026, 11, 25, 4, 50),
      );
      expect(
        parseGuideDate('20261124135000 Z'),
        DateTime.utc(2026, 11, 24, 13, 50),
      );
      expect(
        parseGuideDate('20261124135000 +01:00'),
        DateTime.utc(2026, 11, 24, 12, 50),
      );
    });

    test('sans décalage : UTC ; sans secondes : acceptée', () {
      expect(
        parseGuideDate('20261124135000'),
        DateTime.utc(2026, 11, 24, 13, 50),
      );
      expect(
        parseGuideDate('202611241350 +0100'),
        DateTime.utc(2026, 11, 24, 12, 50),
      );
    });

    test('date illisible : null', () {
      for (final text in [
        '',
        'demain',
        '2026-11-24 13:50:00',
        '20261324135000 +0100',
        '20261124135000 +01',
        '20261124135000 Europe/Paris',
      ]) {
        expect(parseGuideDate(text), isNull, reason: text);
      }
    });
  });

  group('lecture', () {
    test('titres, résumés, entités et CDATA, coupés en tout endroit', () async {
      // Chaque taille coupe ailleurs : dans une entité, un caractère accentué
      // (2 octets), une balise ou un CDATA.
      for (final chunk in [1, 2, 3, 5, 7, 11, 64, 1 << 16]) {
        final guide = await _read(
          chunk: chunk,
          _xml(
            '<channel id="a.fr"><display-name>Ignoré</display-name></channel>'
            '${_programme('20261124130000 +0100', '20261124140000 +0100', 'L&apos;été &amp; &quot;Noël&quot; &lt;3', extra: '<desc>Résumé <![CDATA[avec <b>balise</b>]]> fin</desc>')}'
            '${_programme('20261124140000 +0100', '20261124150000 +0100', '<![CDATA[Café & co]]>')}',
          ),
        );
        final [first, second] = guide.programmes['a.fr']!;
        expect(first.title, 'L\'été & "Noël" <3');
        expect(first.description, 'Résumé avec <b>balise</b> fin');
        expect(first.start, DateTime.utc(2026, 11, 24, 12));
        expect(first.stop, DateTime.utc(2026, 11, 24, 13));
        expect(second.title, 'Café & co');
        expect(second.description, isNull);
        expect(guide.channels, {'a.fr', 'b.fr'});
      }
    });

    test(
      'titre et résumé sans blancs autour ; résumé blanc = absent',
      () async {
        final guide = await _read(
          _xml(
            _programme(
              '20261124130000 +0100',
              '20261124140000 +0100',
              '\n  Journal  \n',
              extra: '<desc>   </desc>',
            ),
          ),
        );
        expect(guide.programmes['a.fr']!.single.title, 'Journal');
        expect(guide.programmes['a.fr']!.single.description, isNull);
      },
    );

    test('plusieurs titres (langues) : le premier', () async {
      final guide = await _read(
        _xml(
          '<programme start="20261124130000 +0100" stop="20261124140000 +0100" '
          'channel="a.fr"><title lang="fr">Premier</title>'
          '<title lang="en">First</title></programme>',
        ),
      );
      expect(_titles(guide), ['Premier']);
    });

    test('chaîne non visible écartée, correspondance exacte de l’id', () async {
      final guide = await _read(
        _xml(
          '${_programme('20261124130000 +0100', '20261124140000 +0100', 'A')}'
          '${_programme('20261124130000 +0100', '20261124140000 +0100', 'B', channel: 'b.fr')}'
          '${_programme('20261124130000 +0100', '20261124140000 +0100', 'C', channel: 'c.fr')}'
          '${_programme('20261124130000 +0100', '20261124140000 +0100', 'A maj', channel: 'A.fr')}',
        ),
        channels: {'a.fr', 'b.fr'},
      );
      expect(guide.programmes.keys, unorderedEquals(['a.fr', 'b.fr']));
      expect(_titles(guide), ['A']);
      expect(_titles(guide, 'b.fr'), ['B']);
    });

    test('fenêtre : de maintenant − 2 h jusqu’à la fin des données', () async {
      final guide = await _read(
        _xml(
          // Fini 2 h 10 avant : écarté. Fini 1 h 50 avant : gardé.
          '${_programme('20261124080000 +0100', '20261124105000 +0100', 'Trop vieux')}'
          '${_programme('20261124105000 +0100', '20261124111000 +0100', 'Récent')}'
          '${_programme('20261127200000 +0100', '20261127210000 +0100', 'Dans 3 jours')}',
        ),
      );
      expect(_titles(guide), ['Récent', 'Dans 3 jours']);
    });

    test('stop absent : fin = début du suivant ; le dernier sans fin écarté', () async {
      final guide = await _read(
        _xml(
          '${_programme('20261124130000 +0100', null, 'Sans fin')}'
          '${_programme('20261124143000 +0100', '20261124150000 +0100', 'Suivant')}'
          '${_programme('20261124150000 +0100', null, 'Dernier')}',
        ),
      );
      final [first, second] = guide.programmes['a.fr']!;
      expect(first.title, 'Sans fin');
      expect(first.stop, DateTime.utc(2026, 11, 24, 13, 30));
      expect(second.title, 'Suivant');
    });

    test('désordre, doublons et chevauchements : le suivant l’emporte', () async {
      final guide = await _read(
        _xml(
          '${_programme('20261124150000 +0100', '20261124160000 +0100', 'C')}'
          '${_programme('20261124130000 +0100', '20261124150000 +0100', 'A')}'
          // Chevauche A : A finit à 14 h.
          '${_programme('20261124140000 +0100', '20261124143000 +0100', 'B')}'
          // Même début que C, plus loin dans le fichier : remplace C.
          '${_programme('20261124150000 +0100', '20261124153000 +0100', 'C bis')}',
        ),
      );
      final programmes = guide.programmes['a.fr']!;
      expect(_titles(guide), ['A', 'B', 'C bis']);
      expect(programmes[0].stop, DateTime.utc(2026, 11, 24, 13));
      expect(programmes[2].stop, DateTime.utc(2026, 11, 24, 14, 30));
    });

    test('entrée cassée ignorée seule', () async {
      final guide = await _read(
        _xml(
          '${_programme('hier', '20261124140000 +0100', 'Début illisible')}'
          '${_programme('20261124130000 +0100', 'bientôt', 'Fin illisible, suivant inconnu')}'
          '${_programme('20261124140000 +0100', '20261124130000 +0100', 'Fin avant début')}'
          '${_programme('20261124150000 +0100', '20261124160000 +0100', '   ')}'
          '<programme start="20261124160000 +0100" stop="20261124170000 +0100">'
          '<title>Sans chaîne</title></programme>'
          '<programme start="20261124170000 +0100" stop="20261124180000 +0100" '
          'channel="a.fr"/>'
          '${_programme('20261124180000 +0100', '20261124190000 +0100', 'Bon')}',
        ),
      );
      expect(_titles(guide), ['Bon']);
    });

    test(
      'serveur sans guide (`<tv/>` vide) : guide vide, chaînes notées',
      () async {
        final guide = await _read(_xml(''));
        expect(guide.programmes, isEmpty);
        expect(guide.channels, {'a.fr', 'b.fr'});
        expect(guide.covers(['a.fr']), isTrue);
      },
    );

    test('pas un guide (JSON, HTML, XML cassé) : FormatException', () async {
      for (final text in [
        '{"user_info":{"auth":0}}',
        '<html><body>Erreur</body></html>',
        '',
        _xml('<programme start="x"').replaceFirst('</tv>', ''),
        // Coupé net après un programme : un guide partiel ne doit pas
        // passer pour complet (et rester 24 h en cache).
        _xml(_programme('20261124130000 +0100', '20261124140000 +0100', 'A'))
            .replaceFirst('</tv>', ''),
      ]) {
        await expectLater(
          _read(text),
          throwsA(isA<FormatException>()),
          reason: text,
        );
      }
    });
  });

  group('en cours et suivant', () {
    final guide = Guide(
      channels: const {'a.fr', 'b.fr', 'vide.fr'},
      programmes: {
        'a.fr': [
          Programme(
            start: DateTime.utc(2026, 11, 24, 11),
            stop: DateTime.utc(2026, 11, 24, 12),
            title: 'Matin',
          ),
          Programme(
            start: DateTime.utc(2026, 11, 24, 12),
            stop: DateTime.utc(2026, 11, 24, 13),
            title: 'Midi',
          ),
          // Trou de 13 h à 14 h.
          Programme(
            start: DateTime.utc(2026, 11, 24, 14),
            stop: DateTime.utc(2026, 11, 24, 15),
            title: 'Après-midi',
          ),
        ],
        'b.fr': [
          Programme(
            start: DateTime.utc(2026, 11, 24, 12, 30),
            stop: DateTime.utc(2026, 11, 24, 12, 45),
            title: 'Court',
          ),
        ],
      },
    );

    String? titleOf(Programme? p) => p?.title;

    test('à un instant donné : en cours, puis suivant', () {
      final (:current, :next) = guide.nowNext(
        'a.fr',
        DateTime.utc(2026, 11, 24, 12, 20),
      );
      expect(titleOf(current), 'Midi');
      expect(titleOf(next), 'Après-midi');
    });

    test('à l’heure pile : le programme qui commence', () {
      final at = DateTime.utc(2026, 11, 24, 12);
      expect(titleOf(guide.nowNext('a.fr', at).current), 'Midi');
    });

    test('dans un trou : rien en cours, le suivant', () {
      final (:current, :next) = guide.nowNext(
        'a.fr',
        DateTime.utc(2026, 11, 24, 13, 30),
      );
      expect(current, isNull);
      expect(titleOf(next), 'Après-midi');
    });

    test('après la fin, chaîne vide, inconnue ou sans id : rien', () {
      final late = DateTime.utc(2026, 11, 24, 16);
      for (final id in ['a.fr', 'vide.fr', 'inconnue.fr', null]) {
        final (:current, :next) = guide.nowNext(id, id == 'a.fr' ? late : _now);
        expect(current, isNull, reason: id);
        expect(next, isNull, reason: id);
      }
    });

    test('progression du programme en cours, de 0 à 1', () {
      final midi = guide.programmes['a.fr']![1];
      expect(midi.progress(DateTime.utc(2026, 11, 24, 12, 15)), 0.25);
      expect(midi.progress(DateTime.utc(2026, 11, 24, 11)), 0);
      expect(midi.progress(DateTime.utc(2026, 11, 24, 14)), 1);
    });

    test(
      'prochain changement : la plus proche fin ou le plus proche début',
      () {
        expect(
          guide.nextChange(DateTime.utc(2026, 11, 24, 12, 20)),
          DateTime.utc(2026, 11, 24, 12, 30),
        );
        expect(
          guide.nextChange(DateTime.utc(2026, 11, 24, 12, 40)),
          DateTime.utc(2026, 11, 24, 12, 45),
        );
        expect(
          guide.nextChange(DateTime.utc(2026, 11, 24, 13, 30)),
          DateTime.utc(2026, 11, 24, 14),
        );
        expect(guide.nextChange(DateTime.utc(2026, 11, 24, 15)), isNull);
      },
    );

    test('programmes d’une plage : ceux qui la touchent, dans l’ordre', () {
      final between = guide.between(
        'a.fr',
        DateTime.utc(2026, 11, 24, 11, 30),
        DateTime.utc(2026, 11, 24, 14),
      );
      expect([for (final p in between) p.title], ['Matin', 'Midi']);
      expect(guide.between('inconnue.fr', _now, _now), isEmpty);
    });

    test('couverture : toutes les chaînes demandées ont été lues', () {
      expect(guide.covers(['a.fr', 'vide.fr']), isTrue);
      expect(guide.covers(['a.fr', 'c.fr']), isFalse);
      expect(Guide.empty.covers(const []), isTrue);
    });
  });

  group('cache', () {
    test('200 guides générés : relus, puis réencodés à l’identique', () {
      final gen = Gen(79);
      for (var i = 0; i < 200; i++) {
        final guide = gen.guide();
        final first = jsonEncode(guide.toJson());
        final back = Guide.fromJson(jsonDecode(first))!;
        expect(jsonEncode(back.toJson()), first, reason: 'itération $i');
        expect(back.channels, guide.channels);
        expect(back.programmes.keys, guide.programmes.keys);
      }
    });

    test('version inconnue ou fichier abîmé : null, jamais d’exception', () {
      final gen = Gen(80);
      expect(
        Guide.fromJson({'version': 2, 'channels': [], 'programmes': {}}),
        isNull,
      );
      expect(Guide.fromJson('texte'), isNull);
      for (var i = 0; i < 200; i++) {
        final json = jsonDecode(jsonEncode(gen.guide().toJson()));
        final guide = Guide.fromJson(gen.mutate(json));
        if (guide == null) continue;
        // Ce qui est relu reste utilisable.
        for (final id in guide.channels) {
          guide.nowNext(id, _now);
        }
      }
    });
  });
}
