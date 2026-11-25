import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart'
    show XmlDefaultEntityMapping, XmlNullEntityMapping;
import 'package:xml/xml_events.dart';

import '../server/json_read.dart';

/// Un programme du guide, en UTC.
final class Programme {
  const Programme({
    required this.start,
    required this.stop,
    required this.title,
    this.description,
  });

  final DateTime start;
  final DateTime stop;
  final String title;
  final String? description;

  /// Part écoulée à [at], de 0 à 1.
  double progress(DateTime at) {
    final total = stop.difference(start).inSeconds;
    return (at.difference(start).inSeconds / total).clamp(0, 1).toDouble();
  }
}

/// Programme en cours (absent dans un trou du guide) et le suivant.
typedef NowNext = ({Programme? current, Programme? next});

const NowNext _nothing = (current: null, next: null);

/// Guide des programmes des chaînes demandées ([channels], ids
/// `epg_channel_id`) : par chaîne, des programmes triés, sans chevauchement.
final class Guide {
  const Guide({required this.channels, required this.programmes});

  static const empty = Guide(channels: {}, programmes: {});

  /// Chaînes cherchées dans le guide, qu'il en ait des programmes ou non :
  /// une chaîne absente du guide ne relance pas son téléchargement.
  final Set<String> channels;
  final Map<String, List<Programme>> programmes;

  /// Toutes les chaînes [ids] ont été cherchées : inutile de retélécharger.
  bool covers(Iterable<String> ids) => ids.every(channels.contains);

  NowNext nowNext(String? channel, DateTime at) {
    final list = programmes[channel];
    if (list == null) return _nothing;
    final i = _firstEndingAfter(list, at);
    if (i == list.length) return _nothing;
    final programme = list[i];
    if (programme.start.isAfter(at)) return (current: null, next: programme);
    return (current: programme, next: i + 1 < list.length ? list[i + 1] : null);
  }

  /// Programmes de [channel] qui touchent la plage de [from] à [to].
  List<Programme> between(String channel, DateTime from, DateTime to) {
    final list = programmes[channel];
    if (list == null) return const [];
    final first = _firstEndingAfter(list, from);
    var end = first;
    while (end < list.length && list[end].start.isBefore(to)) {
      end++;
    }
    return list.sublist(first, end);
  }

  /// Prochain instant où un « en cours » change, toutes chaînes confondues :
  /// la fin d'un programme en cours ou le début du suivant après un trou.
  DateTime? nextChange(DateTime at) {
    DateTime? soonest;
    for (final list in programmes.values) {
      final i = _firstEndingAfter(list, at);
      if (i == list.length) continue;
      final p = list[i];
      final change = p.start.isAfter(at) ? p.start : p.stop;
      if (soonest == null || change.isBefore(soonest)) soonest = change;
    }
    return soonest;
  }

  /// Cache local (D-085) : dates en secondes, résumé omis s'il n'y en a pas.
  Map<String, Object?> toJson() => {
    'version': 1,
    'channels': [...channels],
    'programmes': {
      for (final MapEntry(key: id, value: list) in programmes.entries)
        id: [
          for (final p in list)
            [
              p.start.millisecondsSinceEpoch ~/ 1000,
              p.stop.millisecondsSinceEpoch ~/ 1000,
              p.title,
              ?p.description,
            ],
        ],
    },
  };

  /// Relit [toJson] ; `null` si ce n'est pas un cache de cette version. Une
  /// entrée abîmée est ignorée seule, l'ordre des programmes est vérifié.
  static Guide? fromJson(Object? json) {
    final map = asMap(json);
    if (asInt(map['version']) != 1) return null;
    final programmes = <String, List<Programme>>{};
    for (final MapEntry(:key, :value) in asMap(map['programmes']).entries) {
      final list = <Programme>[];
      for (final entry in asList(value)) {
        final fields = asList(entry);
        if (fields.length < 3) continue;
        final start = asDate(fields[0]);
        final stop = asDate(fields[1]);
        final title = asString(fields[2]);
        if (start == null || stop == null || title == null) continue;
        if (!stop.isAfter(start)) continue;
        if (list.isNotEmpty && start.isBefore(list.last.stop)) continue;
        list.add(
          Programme(
            start: start,
            stop: stop,
            title: title,
            description: fields.length > 3 ? asString(fields[3]) : null,
          ),
        );
      }
      if (list.isNotEmpty) programmes[key] = list;
    }
    return Guide(
      channels: {for (final id in asList(map['channels'])) ?asString(id)},
      programmes: programmes,
    );
  }
}

/// Premier programme de [list] qui finit après [at] (recherche binaire).
int _firstEndingAfter(List<Programme> list, DateTime at) {
  var low = 0;
  var high = list.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (list[mid].stop.isAfter(at)) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return low;
}

/// `20261124135000 +0100` (secondes et décalage facultatifs, `Z`, `+01:00`)
/// en UTC ; sans décalage, l'heure est prise pour de l'UTC. `null` si
/// illisible.
DateTime? parseGuideDate(String text) {
  final match = _date.firstMatch(text.trim());
  if (match == null) return null;
  int part(int i) => int.parse(match[i] ?? '0');
  final month = part(2);
  final day = part(3);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (part(4) > 23 || part(5) > 59 || part(6) > 60) return null;
  final local = DateTime.utc(part(1), month, day, part(4), part(5), part(6));
  // Groupe 7 : `Z` ; 8 : signe ; 9 et 10 : heures et minutes du décalage.
  final offset = switch (match[8]) {
    null => Duration.zero,
    final sign =>
      Duration(hours: part(9), minutes: part(10)) * (sign == '-' ? -1 : 1),
  };
  return local.subtract(offset);
}

final _date = RegExp(
  r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?(?:\s*(?:(Z)|([+-])(\d{2}):?(\d{2})))?$',
);

/// Lectures du guide faites dans cet isolate : un test vérifie qu'il n'y en
/// a aucune sur celui de l'interface.
@visibleForTesting
var guideReadsInThisIsolate = 0;

/// Lit un guide XMLTV en flux, sans le garder en mémoire : seuls les
/// programmes des chaînes [channels] qui finissent après « [now] − 2 h »
/// sont gardés. Lève [FormatException] si ce n'est pas un guide complet
/// (jusqu'à `</tv>`). La DTD n'est jamais lue.
///
/// Fonction de premier niveau : appelée dans un isolate, le guide d'un
/// fournisseur dépasse 30 Mo.
Future<Guide> readGuide(
  Stream<List<int>> bytes, {
  required Set<String> channels,
  required DateTime now,
}) async {
  guideReadsInThisIsolate++;
  final reader = _GuideReader(channels);
  await for (final events
      in bytes
          .transform(const Utf8Decoder(allowMalformed: true))
          .toXmlEvents(
            // Entités décodées par `_GuideReader` : un texte coupé entre deux
            // morceaux du flux arrive en deux événements, et `&amp;` coupé en
            // `&am` + `p;` ne serait décodé ni dans l'un ni dans l'autre.
            entityMapping: const XmlNullEntityMapping(),
          )) {
    events.forEach(reader.add);
  }
  if (!reader.complete) throw const FormatException('Guide incomplet');
  return Guide(
    channels: channels,
    programmes: reader.programmes(now.subtract(const Duration(hours: 2))),
  );
}

/// [readGuide] sur un fichier téléchargé.
Future<Guide> readGuideFile(
  String path, {
  required Set<String> channels,
  required DateTime now,
}) => readGuide(File(path).openRead(), channels: channels, now: now);

/// Programme tel que lu, avant de résoudre les fins absentes.
typedef _Raw = ({DateTime start, DateTime? stop, String title, String? desc});

final class _GuideReader {
  _GuideReader(this._channels);

  final Set<String> _channels;
  final _raw = <String, List<_Raw>>{};
  var complete = false;

  // Programme en cours de lecture (chaîne gardée seulement).
  String? _channel;
  String? _start;
  String? _stop;
  String? _title;
  String? _desc;

  /// Élément dont le texte est relevé (`title` ou `desc`).
  String? _field;
  final _text = StringBuffer();

  /// Texte brut pas encore décodé : les entités d'un texte coupé en
  /// plusieurs événements se décodent une fois le texte recollé.
  final _pending = StringBuffer();

  static const _entities = XmlDefaultEntityMapping.xml();

  void _flush() {
    _text.write(_entities.decode(_pending.toString()));
    _pending.clear();
  }

  void add(XmlEvent event) {
    switch (event) {
      case XmlStartElementEvent(name: 'tv', isSelfClosing: true):
        complete = true;
      case XmlStartElementEvent(
        name: 'programme',
        isSelfClosing: false,
        :final attributes,
      ):
        final channel = _attribute(attributes, 'channel');
        if (channel != null && _channels.contains(channel)) {
          _channel = channel;
          _start = _attribute(attributes, 'start');
          _stop = _attribute(attributes, 'stop');
          _title = _desc = null;
        }
      case XmlStartElementEvent(:final name, isSelfClosing: false)
          when _channel != null && (name == 'title' || name == 'desc'):
        _field = name;
        _text.clear();
        _pending.clear();
      case XmlTextEvent(:final value) when _field != null:
        _pending.write(value);
      case XmlCDATAEvent(:final value) when _field != null:
        _flush();
        _text.write(value);
      case XmlEndElementEvent(:final name) when name == _field:
        _flush();
        final text = _text.toString().trim();
        if (text.isNotEmpty) {
          // Plusieurs titres (une langue chacun) : le premier.
          if (name == 'title') {
            _title ??= text;
          } else {
            _desc ??= text;
          }
        }
        _field = null;
      case XmlEndElementEvent(name: 'programme') when _channel != null:
        _keep();
        _channel = _field = null;
      case XmlEndElementEvent(name: 'tv'):
        complete = true;
      default:
    }
  }

  /// Garde le programme lu s'il est valide ; sinon l'ignore, lui seul.
  void _keep() {
    final start = parseGuideDate(_start ?? '');
    final stopText = _stop;
    final stop = stopText == null ? null : parseGuideDate(stopText);
    final title = _title;
    if (start == null || title == null) return;
    if (stopText != null && (stop == null || !stop.isAfter(start))) return;
    (_raw[_channel!] ??= []).add((
      start: start,
      stop: stop,
      title: title,
      desc: _desc,
    ));
  }

  /// Par chaîne, programmes triés ; un programme sans fin finit au début du
  /// suivant, un chevauchement aussi (le suivant l'emporte), et de deux
  /// programmes au même début, le dernier du fichier reste. Seuls ceux qui
  /// finissent après [cutoff] sont gardés.
  Map<String, List<Programme>> programmes(DateTime cutoff) => {
    for (final MapEntry(key: id, value: raw) in _raw.entries)
      if (_resolve(raw, cutoff) case final list when list.isNotEmpty) id: list,
  };

  static List<Programme> _resolve(List<_Raw> raw, DateTime cutoff) {
    // `List.sort` n'est pas stable : l'index départage les égalités.
    final sorted = raw.indexed.toList()
      ..sort((a, b) {
        final byStart = a.$2.start.compareTo(b.$2.start);
        return byStart != 0 ? byStart : a.$1.compareTo(b.$1);
      });
    final result = <Programme>[];
    for (var i = 0; i < sorted.length; i++) {
      final p = sorted[i].$2;
      final next = i + 1 < sorted.length ? sorted[i + 1].$2 : null;
      if (next != null && next.start == p.start) continue;
      var stop = p.stop;
      if (next != null && (stop == null || stop.isAfter(next.start))) {
        stop = next.start;
      }
      // Le dernier sans fin : sa durée est inconnue.
      if (stop == null || !stop.isAfter(cutoff)) continue;
      result.add(
        Programme(
          start: p.start,
          stop: stop,
          title: p.title,
          description: p.desc,
        ),
      );
    }
    return result;
  }
}

String? _attribute(List<XmlEventAttribute> attributes, String name) {
  for (final attribute in attributes) {
    if (attribute.name == name) {
      return _GuideReader._entities.decode(attribute.value);
    }
  }
  return null;
}
