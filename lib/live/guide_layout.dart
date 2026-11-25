import 'dart:math';

import 'channel.dart';
import 'guide.dart';

/// Une case d'une ligne de la grille : un programme, ou un temps sans
/// programme (trou du guide, fin des données, chaîne sans guide). Ses heures
/// sont coupées aux bords de l'axe ; [programme] garde les vraies.
final class GuideSlot {
  const GuideSlot(this.start, this.stop, [this.programme]);

  final DateTime start;
  final DateTime stop;
  final Programme? programme;

  /// OK sur cette case à [at] lance la chaîne : programme en cours, ou rien
  /// d'annoncé. Sinon, OK ouvre le détail du programme.
  bool playsAt(DateTime at) {
    final p = programme;
    return p == null || (!p.start.isAfter(at) && p.stop.isAfter(at));
  }
}

typedef IndexRange = ({int first, int end});

/// Mise en page de la grille des programmes : une ligne par chaîne, l'axe
/// des heures de [from] à [to], linéaire (`pixelsPerMinute`). Calculs purs,
/// les widgets ne font que poser les cases où elle le dit.
final class GuideLayout {
  GuideLayout({required this.from, required this.to, required this.rows})
    : width = _minutes(from, to) * pixelsPerMinute;

  /// Les programmes des [channels] sur la fenêtre de [window].
  factory GuideLayout.of(List<Channel> channels, Guide guide, DateTime now) {
    final all = [
      for (final channel in channels)
        guide.programmes[channel.epgChannelId] ?? const <Programme>[],
    ];
    final (:from, :to) = window(now, all);
    return GuideLayout(
      from: from,
      to: to,
      rows: [
        for (final channel in channels)
          switch (channel.epgChannelId) {
            final id? => guide.between(id, from, to),
            null => const <Programme>[],
          },
      ],
    );
  }

  static const pixelsPerMinute = 4.0;
  static const rowHeight = 64.0;

  /// Un programme de quelques minutes reste lisible (et visable).
  static const minCellWidth = 48.0;

  /// Espace laissé autour d'une case que le focus fait apparaître.
  static const revealMargin = 32.0;

  static const _step = Duration(minutes: 30);

  /// Axe des heures : de maintenant − 2 h (à la demi-heure) à la fin des
  /// données (à la demi-heure), au moins jusqu'à maintenant + 2 h.
  static ({DateTime from, DateTime to}) window(
    DateTime now,
    List<List<Programme>> rows,
  ) {
    final from = _floor(now.subtract(const Duration(hours: 2)));
    var to = now.add(const Duration(hours: 2));
    for (final row in rows) {
      if (row.isEmpty) continue;
      final end = _ceil(row.last.stop);
      if (end.isAfter(to)) to = end;
    }
    return (from: from, to: to);
  }

  final DateTime from;
  final DateTime to;

  /// Programmes de chaque chaîne, triés, sans chevauchement.
  final List<List<Programme>> rows;

  /// Largeur de l'axe entier, en pixels.
  final double width;

  int get rowCount => rows.length;
  double get height => rows.length * rowHeight;

  /// Cases et bords de chaque ligne, calculés à la première demande : seules
  /// les lignes vues coûtent.
  final _rows = <int, _Row>{};

  double x(DateTime t) =>
      (_minutes(from, t) * pixelsPerMinute).clamp(0, width).toDouble();

  /// Heure à la position [x] de l'axe (inverse de [x], sans borne).
  DateTime timeAt(double x) =>
      from.add(Duration(microseconds: (x / pixelsPerMinute * 60e6).round()));

  /// [t] est sur l'axe.
  bool shows(DateTime t) => !t.isBefore(from) && t.isBefore(to);

  List<GuideSlot> slots(int row) => _row(row).slots;
  double left(int row, int i) => _row(row).lefts[i];
  double right(int row, int i) => _row(row).rights[i];

  /// Heures des repères de l'axe (chaque demi-heure) entre [viewLeft] et
  /// [viewRight] ; celui juste avant [viewLeft] aussi, pour que son texte
  /// glisse hors de l'écran au lieu d'y disparaître d'un coup.
  List<DateTime> ticks(double viewLeft, double viewRight) {
    final step = _step.inMinutes * pixelsPerMinute;
    final first = max(0, (viewLeft / step).floor() - 1);
    return [
      for (var i = first; i * step < min(viewRight, width); i++)
        from.add(_step * i),
    ];
  }

  /// Cases de [row] qui touchent la bande de [viewLeft] à [viewRight].
  IndexRange visible(int row, double viewLeft, double viewRight) {
    final r = _row(row);
    final first = _firstWhere(r.rights.length, (i) => r.rights[i] > viewLeft);
    final end = _firstWhere(r.lefts.length, (i) => r.lefts[i] >= viewRight);
    return (first: first, end: max(first, end));
  }

  /// Lignes qui touchent la bande verticale de [offset] sur [extent].
  static IndexRange visibleRows(
    double offset,
    double extent, {
    required int rowCount,
  }) => (
    first: (offset / rowHeight).floor().clamp(0, rowCount),
    end: ((offset + extent) / rowHeight).ceil().clamp(0, rowCount),
  );

  /// Part visible d'une case de [left] à [right] dans la bande de [viewLeft]
  /// à [viewRight] : une case coupée au bord y est posée, son titre reste lu.
  /// Une case hors de la bande (préparée en avance) reste entière.
  static (double, double) clip(
    double left,
    double right,
    double viewLeft,
    double viewRight,
  ) => right <= viewLeft || left >= viewRight
      ? (left, right)
      : (max(left, viewLeft), min(right, viewRight));

  /// Case de [row] qui couvre [t] : la première ou la dernière hors de l'axe.
  int slotAt(int row, DateTime t) {
    final slots = _row(row).slots;
    final i = _firstWhere(slots.length, (i) => slots[i].stop.isAfter(t));
    return min(i, slots.length - 1);
  }

  /// Case voisine de [i] dans [row] (`step` = 1 ou −1), `null` au bout.
  int? neighbour(int row, int i, int step) {
    final next = i + step;
    return next < 0 || next >= slots(row).length ? null : next;
  }

  /// Ligne voisine, `null` au bout.
  int? neighbourRow(int row, int step) {
    final next = row + step;
    return next < 0 || next >= rows.length ? null : next;
  }

  /// Heure que ↑ ↓ gardent depuis la case [i] de [row], la grille décalée
  /// de [offset] : son début, ou l'heure du bord gauche si elle a commencé
  /// hors de l'écran (sinon une émission longue ramènerait ↓ des heures en
  /// arrière).
  DateTime anchorOf(int row, int i, double offset) {
    final start = slots(row)[i].start;
    final edge = timeAt(offset);
    return edge.isAfter(start) && edge.isBefore(slots(row)[i].stop)
        ? edge
        : start;
  }

  /// Décalage qui montre la bande de [start] à [end] dans une fenêtre de
  /// [extent] décalée de [offset] (les deux axes) ; inchangé si elle se voit
  /// déjà. Une case plus large que la fenêtre montre son début, sauf si elle
  /// la couvre déjà.
  static double reveal(double offset, double extent, double start, double end) {
    const m = revealMargin;
    if (end - start + 2 * m > extent) {
      if (offset >= start - m && offset + extent <= end + m) return offset;
      return max(0, start - m);
    }
    if (start - m < offset) return max(0, start - m);
    if (end + m > offset + extent) return end + m - extent;
    return offset;
  }

  _Row _row(int row) => _rows[row] ??= _build(rows[row]);

  _Row _build(List<Programme> programmes) {
    final slots = <GuideSlot>[];
    var at = from;
    for (final p in programmes) {
      if (!p.stop.isAfter(at) || !p.start.isBefore(to)) continue;
      final start = p.start.isAfter(at) ? p.start : at;
      if (start.isAfter(at)) slots.add(GuideSlot(at, start));
      final stop = p.stop.isBefore(to) ? p.stop : to;
      slots.add(GuideSlot(start, stop, p));
      at = stop;
    }
    if (at.isBefore(to) || slots.isEmpty) slots.add(GuideSlot(at, to));
    // Bords : une case trop courte prend la largeur minimale sur la
    // suivante, qui commence plus loin mais finit à sa vraie heure.
    final lefts = <double>[];
    final rights = <double>[];
    var previous = 0.0;
    for (final slot in slots) {
      final left = max(x(slot.start), previous);
      final right = min(max(x(slot.stop), left + minCellWidth), width);
      lefts.add(min(left, right));
      rights.add(right);
      previous = right;
    }
    return _Row(slots, lefts, rights);
  }
}

final class _Row {
  const _Row(this.slots, this.lefts, this.rights);

  final List<GuideSlot> slots;
  final List<double> lefts;
  final List<double> rights;
}

double _minutes(DateTime from, DateTime to) =>
    to.difference(from).inMicroseconds / Duration.microsecondsPerMinute;

DateTime _floor(DateTime t) {
  final step = GuideLayout._step.inMicroseconds;
  final us = t.microsecondsSinceEpoch;
  return DateTime.fromMicrosecondsSinceEpoch(us - us % step, isUtc: true);
}

DateTime _ceil(DateTime t) {
  final floor = _floor(t);
  return floor.isBefore(t) ? floor.add(GuideLayout._step) : floor;
}

/// Premier indice de 0 à [length] où [test] devient vrai (recherche binaire,
/// [test] faux puis vrai).
int _firstWhere(int length, bool Function(int) test) {
  var low = 0;
  var high = length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (test(mid)) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return low;
}
