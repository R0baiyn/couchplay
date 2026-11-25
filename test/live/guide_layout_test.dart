import 'package:couchplay/live/channel.dart';
import 'package:couchplay/live/guide.dart';
import 'package:couchplay/live/guide_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixed_guide.dart';

void main() {
  // Une heure ronde : l'axe part de maintenant − 2 h, arrondi à la demi-heure.
  final now = DateTime.utc(2026, 11, 25, 20, 10);
  final from = DateTime.utc(2026, 11, 25, 18);
  const perMinute = GuideLayout.pixelsPerMinute;

  /// Programme de [a] à [b] minutes après [from].
  Programme p(int a, int b, [String title = 'P']) =>
      programmeAt(from, a * 60, b * 60, title);

  GuideLayout layout(List<List<Programme>> rows, {int minutes = 240}) =>
      GuideLayout(
        from: from,
        to: from.add(Duration(minutes: minutes)),
        rows: rows,
      );

  group('axe des heures', () {
    test('fenêtre : de maintenant − 2 h (demi-heure) à la fin des données', () {
      final window = GuideLayout.window(now, [
        [p(0, 60)],
        [p(100, 400)],
        [],
      ]);
      expect(window.from, from);
      expect(window.to, from.add(const Duration(minutes: 420)));
    });

    test('fin des données avant maintenant + 2 h, ou aucune : axe de 4 h', () {
      final empty = GuideLayout.window(now, [[], []]);
      expect(empty.from, from);
      expect(empty.to, now.add(const Duration(hours: 2)));
      expect(
        GuideLayout.window(now, [
          [p(0, 30)],
        ]).to,
        empty.to,
      );
    });

    test('position et largeur proportionnelles à l’heure', () {
      final l = layout([
        [p(30, 90)],
      ]);
      expect(l.x(from), 0);
      expect(l.x(from.add(const Duration(minutes: 90))), 90 * perMinute);
      expect(l.width, 240 * perMinute);
      final slot = l.slots(0)[1];
      expect(slot.programme?.title, 'P');
      expect((l.left(0, 1), l.right(0, 1)), (30 * perMinute, 90 * perMinute));
    });
  });

  test('repères de l’axe : chaque demi-heure visible, et celui d’avant', () {
    final l = layout([[]]);
    const half = 30 * perMinute;
    DateTime at(int m) => from.add(Duration(minutes: m));
    expect(l.ticks(0, half * 2), [at(0), at(30)]);
    expect(l.ticks(half * 2.5, half * 4), [at(30), at(60), at(90)]);
    expect(l.ticks(0, l.width * 2).last, at(210));
  });

  test('heure d’une position, et heures sur l’axe', () {
    final l = layout([[]]);
    expect(l.timeAt(90 * perMinute), from.add(const Duration(minutes: 90)));
    expect(l.x(l.timeAt(123.5)), closeTo(123.5, 0.001));
    expect(l.shows(from), isTrue);
    expect(l.shows(from.add(const Duration(minutes: 239))), isTrue);
    expect(l.shows(from.add(const Duration(minutes: 240))), isFalse);
    expect(l.shows(from.subtract(const Duration(seconds: 1))), isFalse);
  });

  group('cases d’une ligne', () {
    test('trou entre deux programmes : une case vide entre les deux', () {
      final l = layout([
        [p(0, 60, 'A'), p(90, 240, 'B')],
      ]);
      final slots = l.slots(0);
      expect([for (final s in slots) s.programme?.title], ['A', null, 'B']);
      expect(slots[1].start, from.add(const Duration(minutes: 60)));
      expect(slots[1].stop, from.add(const Duration(minutes: 90)));
    });

    test('chaîne sans programme : une seule case sur tout l’axe', () {
      final l = layout([[]]);
      expect(l.slots(0), hasLength(1));
      expect(l.slots(0).single.programme, isNull);
      expect((l.left(0, 0), l.right(0, 0)), (0, l.width));
    });

    test('données finies avant la fin de l’axe : case vide jusqu’au bout', () {
      final l = layout([
        [p(0, 120)],
      ]);
      expect(l.slots(0), hasLength(2));
      expect(l.slots(0).last.programme, isNull);
      expect(l.right(0, 1), l.width);
    });

    test('programme commencé avant l’axe : coupé au début de l’axe', () {
      final l = layout([
        [p(-30, 60)],
      ]);
      expect(l.slots(0).first.start, from);
      expect(l.slots(0).first.programme?.start, p(-30, 60).start);
      expect(l.left(0, 0), 0);
    });

    test('largeur minimale : la case courte empiète sur la suivante, '
        'dont la fin ne bouge pas', () {
      // Trois programmes de 2 min puis un long.
      final l = layout([
        [p(0, 2), p(2, 4), p(4, 6), p(6, 120)],
      ]);
      const min = GuideLayout.minCellWidth;
      expect(l.right(0, 0) - l.left(0, 0), min);
      expect(l.left(0, 1), l.right(0, 0));
      expect(l.right(0, 1) - l.left(0, 1), min);
      expect(l.right(0, 2) - l.left(0, 2), min);
      expect(l.left(0, 3), 3 * min);
      expect(l.right(0, 3), 120 * perMinute);
    });

    test('largeur minimale au bout de l’axe : jamais au-delà', () {
      final l = layout([
        [p(0, 239), p(239, 240)],
      ]);
      expect(l.right(0, 1), l.width);
      expect(l.left(0, 1), lessThanOrEqualTo(l.right(0, 1)));
    });
  });

  group('cases visibles', () {
    final l = layout([
      [p(0, 60), p(60, 120), p(120, 180), p(180, 240)],
    ]);

    test('seules les cases qui touchent la fenêtre', () {
      expect(l.visible(0, 70 * perMinute, 130 * perMinute), (first: 1, end: 3));
      expect(l.visible(0, 0, 10 * perMinute), (first: 0, end: 1));
      expect(l.visible(0, 60 * perMinute, 61 * perMinute), (first: 1, end: 2));
    });

    test('case coupée au bord de la fenêtre : posée sur sa part visible', () {
      expect(GuideLayout.clip(100, 300, 150, 400), (150.0, 300.0));
      expect(GuideLayout.clip(100, 300, 0, 200), (100.0, 200.0));
      expect(GuideLayout.clip(100, 300, 0, 500), (100.0, 300.0));
      // Hors de la fenêtre (préparée en avance) : entière.
      expect(GuideLayout.clip(100, 300, 400, 500), (100.0, 300.0));
      expect(GuideLayout.clip(100, 300, 0, 50), (100.0, 300.0));
    });

    test('lignes visibles', () {
      const h = GuideLayout.rowHeight;
      expect(GuideLayout.visibleRows(h * 2.5, h * 2, rowCount: 300), (
        first: 2,
        end: 5,
      ));
      expect(GuideLayout.visibleRows(0, h * 10, rowCount: 3), (
        first: 0,
        end: 3,
      ));
    });
  });

  group('déplacements', () {
    final l = layout([
      [p(0, 60, 'A'), p(60, 120, 'B'), p(150, 240, 'C')],
      [p(0, 200, 'D')],
      [],
    ]);

    test('case qui couvre une heure (pour ↑ ↓)', () {
      DateTime at(int m) => from.add(Duration(minutes: m));
      expect(l.slotAt(0, at(30)), 0);
      expect(l.slotAt(0, at(60)), 1);
      expect(l.slotAt(0, at(130)), 2); // le trou
      expect(l.slotAt(1, at(210)), 1); // fin des données
      expect(l.slotAt(2, at(100)), 0); // sans programme
      expect(l.slotAt(0, at(-60)), 0);
      expect(l.slotAt(0, at(999)), l.slots(0).length - 1);
    });

    test('suivant / précédent dans la ligne, rien au bout', () {
      expect(l.neighbour(0, 0, 1), 1);
      expect(l.neighbour(0, 1, 1), 2);
      expect(l.neighbour(0, 3, 1), isNull);
      expect(l.neighbour(0, 0, -1), isNull);
      expect(l.neighbour(0, 2, -1), 1);
    });

    test('ligne voisine : rien au-dessus de la 1re ni sous la dernière', () {
      expect(l.neighbourRow(0, -1), isNull);
      expect(l.neighbourRow(0, 1), 1);
      expect(l.neighbourRow(2, 1), isNull);
    });

    test('heure tenue : ↓ ↓ ↑ ↑ revient au même programme', () {
      final anchor = from.add(const Duration(minutes: 70));
      var row = 0;
      var slot = l.slotAt(row, anchor);
      expect(l.slots(row)[slot].programme?.title, 'B');
      for (final step in [1, 1, -1, -1]) {
        row = l.neighbourRow(row, step)!;
        slot = l.slotAt(row, anchor);
      }
      expect(l.slots(row)[slot].programme?.title, 'B');
    });

    test('heure tenue d’une case : son début, ou le bord gauche visible', () {
      expect(l.anchorOf(0, 1, 0), from.add(const Duration(minutes: 60)));
      expect(l.anchorOf(1, 0, 0), from);
      // Case longue commencée hors de l’écran : l’heure du bord gauche.
      expect(
        l.anchorOf(1, 0, 90 * perMinute),
        from.add(const Duration(minutes: 90)),
      );
    });
  });

  group('choix d’une case', () {
    test('OK : en cours ou sans programme → la chaîne ; sinon le détail', () {
      final l = layout([
        [p(0, 60), p(60, 120), p(150, 240)],
      ]);
      final at = from.add(const Duration(minutes: 70));
      expect(
        [for (final s in l.slots(0)) s.playsAt(at)],
        [
          false,
          true,
          true, // le trou
          false,
        ],
      );
    });

    test('lignes tirées des chaînes : sans id de guide ou absente, vide', () {
      final guide = Guide(
        channels: const {'a', 'b'},
        programmes: {
          'a': [p(0, 60, 'A')],
        },
      );
      Channel channel(String id, String? epg) =>
          Channel(id: id, name: id, epgChannelId: epg);
      final l = GuideLayout.of(
        [channel('1', 'a'), channel('2', 'b'), channel('3', null)],
        guide,
        now,
      );
      expect(l.from, from);
      expect(l.rowCount, 3);
      expect(l.slots(0).first.programme?.title, 'A');
      expect(l.slots(1).single.programme, isNull);
      expect(l.slots(2).single.programme, isNull);
    });
  });

  group('défilement qui montre une case', () {
    test('déjà visible : rien ne bouge', () {
      expect(GuideLayout.reveal(100, 500, 200, 300), 100);
    });

    test('à droite : la case vient au bord droit, avec une marge', () {
      expect(
        GuideLayout.reveal(0, 500, 600, 700),
        700 + GuideLayout.revealMargin - 500,
      );
    });

    test('à gauche : la case vient au bord gauche, avec une marge', () {
      expect(
        GuideLayout.reveal(400, 500, 300, 350),
        300 - GuideLayout.revealMargin,
      );
    });

    test('plus large que la fenêtre : son début', () {
      expect(
        GuideLayout.reveal(0, 500, 600, 2000),
        600 - GuideLayout.revealMargin,
      );
    });

    test('plus large que la fenêtre, qui la couvre déjà : rien ne bouge', () {
      expect(GuideLayout.reveal(800, 500, 600, 2000), 800);
    });

    test('jamais avant 0', () {
      expect(GuideLayout.reveal(100, 500, 10, 50), 0);
    });
  });
}
