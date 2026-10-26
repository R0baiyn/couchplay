import 'package:couchplay/server/json_read.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('asInt accepte entiers, chaînes et décimaux entiers', () {
    expect(asInt(12), 12);
    expect(asInt('12'), 12);
    expect(asInt(' 12 '), 12);
    expect(asInt(12.0), 12);
    expect(asInt('12.0'), 12);
    expect(asInt('-3'), -3);
  });

  test('asInt renvoie null pour le reste', () {
    for (final value in [
      null,
      '',
      'abc',
      '12.5',
      12.5,
      double.nan,
      double.infinity,
      true,
      <int>[],
    ]) {
      expect(asInt(value), isNull, reason: '$value');
    }
  });

  test('asDouble accepte nombres et chaînes, virgule décimale comprise', () {
    expect(asDouble(7), 7.0);
    expect(asDouble(7.5), 7.5);
    expect(asDouble('7.5'), 7.5);
    expect(asDouble('7,5'), 7.5);
    expect(asDouble(' 8 '), 8.0);
    for (final value in [null, '', 'abc', '1,2,3', double.nan, false]) {
      expect(asDouble(value), isNull, reason: '$value');
    }
  });

  test('asBool comprend les formes du serveur', () {
    for (final value in [true, 1, '1', 'true', 'TRUE', 'yes', 'on', ' 1 ']) {
      expect(asBool(value), isTrue, reason: '$value');
    }
    for (final value in [false, 0, '0', 'false', 'no', 'off']) {
      expect(asBool(value), isFalse, reason: '$value');
    }
    for (final value in [null, '', 'abc', 2, '2', 0.5]) {
      expect(asBool(value), isNull, reason: '$value');
    }
  });

  test('asString garde le texte, convertit les nombres et ignore le vide', () {
    expect(asString('Inception'), 'Inception');
    expect(asString(' Inception '), ' Inception ');
    expect(asString(42), '42');
    expect(asString(42.0), '42');
    expect(asString(4.5), '4.5');
    for (final value in [
      null,
      '',
      '   ',
      true,
      <String>[],
      <String, Object>{},
    ]) {
      expect(asString(value), isNull, reason: '$value');
    }
  });

  test('asId renvoie toujours une chaîne normalisée', () {
    expect(asId(1234), '1234');
    expect(asId('1234'), '1234');
    expect(asId(' 1234 '), '1234');
    expect(asId(1234.0), '1234');
    expect(asId(null), isNull);
    expect(asId(''), isNull);
  });

  test('asDate lit les secondes epoch et les dates texte', () {
    final expected = DateTime.utc(2026, 10, 26, 12);
    final seconds = expected.millisecondsSinceEpoch ~/ 1000;
    expect(asDate(seconds), expected);
    expect(asDate('$seconds'), expected);
    expect(asDate('2026-10-26'), DateTime(2026, 10, 26));
    expect(asDate('2026-10-26 12:00:00'), DateTime(2026, 10, 26, 12));
    for (final value in [null, '', '0', 0, 'jamais', true]) {
      expect(asDate(value), isNull, reason: '$value');
    }
  });

  test('asList accepte une liste ou un objet indexé, sinon liste vide', () {
    expect(asList([1, 2]), [1, 2]);
    expect(asList({'0': 'a', '1': 'b'}), ['a', 'b']);
    for (final value in [null, '', 3, 'abc']) {
      expect(asList(value), isEmpty, reason: '$value');
    }
  });

  test('asMap accepte un objet, et la liste vide envoyée à la place de {}', () {
    expect(asMap({'a': 1}), {'a': 1});
    expect(asMap({1: 'x'}), {'1': 'x'});
    for (final value in [
      null,
      <Object>[],
      '',
      3,
      [1],
    ]) {
      expect(asMap(value), isEmpty, reason: '$value');
    }
  });
}
