import 'dart:convert';
import 'dart:io';

import 'package:couchplay/live/channel.dart';
import 'package:couchplay/server/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final streams = File('test/fixtures/live_streams.json').readAsStringSync();

  group('parseChannels (fixture)', () {
    final channels = parseChannels(streams);
    Channel byId(String id) => channels.singleWhere((c) => c.id == id);

    test('22 entrées : la radio et la chaîne sans nom sont ignorées', () {
      expect(channels, hasLength(20));
      final ids = channels.map((c) => c.id).toSet();
      // `radio_streams` : écartée au décodage.
      expect(ids, isNot(contains('9022')));
      // Nom vide : entrée invalide, ignorée seule.
      expect(ids, isNot(contains('9017')));
      // Une radio rangée en `live` reste une chaîne (sa catégorie est masquée
      // par le filtre, pas ici).
      expect(ids, contains('9021'));
    });

    test('champs lus avec leurs types', () {
      final first = byId('9001');
      expect(first.number, 1);
      expect(first.name, 'Chaîne 1 HD');
      expect(first.logo, 'https://example.com/logo/1.png');
      expect(first.epgChannelId, 'chaine1.test');
      expect(first.categoryId, '104');
    });

    test('logo vide : null ; logo http gardé', () {
      expect(byId('9003').logo, isNull);
      expect(byId('9002').logo, 'http://example.com/logo/2.png');
    });

    test('id du guide null : null ; id numérique : texte', () {
      expect(byId('9003').epgChannelId, isNull);
      expect(byId('9009').epgChannelId, '12345');
    });

    test('ordre par num', () {
      final numbers = [for (final c in channels) c.number];
      expect(numbers, [...numbers]..sort());
    });
  });

  group('parseChannels (types bizarres)', () {
    List<Channel> parse(List<Object?> entries) =>
        parseChannels(jsonEncode(entries));

    test('nombres en texte, id du guide en nombre, stream_type absent', () {
      final [channel] = parse([
        {
          'num': '7',
          'name': ' Une chaîne ',
          'stream_id': '42',
          'stream_icon': 'pas une adresse',
          'epg_channel_id': 12345,
          'category_id': 104,
        },
      ]);
      expect(channel.id, '42');
      expect(channel.number, 7);
      expect(channel.name, 'Une chaîne');
      expect(channel.logo, isNull);
      expect(channel.epgChannelId, '12345');
      expect(channel.categoryId, '104');
    });

    test('entrées invalides ignorées seules', () {
      final channels = parse([
        'texte',
        null,
        {'name': 'Sans id', 'stream_type': 'live'},
        {'stream_id': 1, 'name': '   ', 'stream_type': 'live'},
        {'stream_id': 2, 'name': 'Radio', 'stream_type': 'radio_streams'},
        {'stream_id': 3, 'name': 'Bonne', 'stream_type': 'live'},
      ]);
      expect([for (final c in channels) c.id], ['3']);
    });

    test('seules les radios sont écartées : `created_live` gardée', () {
      final channels = parse([
        {'stream_id': 1, 'name': 'A', 'stream_type': 'live'},
        {'stream_id': 2, 'name': 'B', 'stream_type': 'created_live'},
        {'stream_id': 3, 'name': 'C', 'stream_type': 'radio_streams'},
      ]);
      expect([for (final c in channels) c.id], ['1', '2']);
    });

    test('ordre par num, stable, sans num à la fin', () {
      final channels = parse([
        {'stream_id': 'a', 'name': 'A', 'num': 3},
        {'stream_id': 'b', 'name': 'B'},
        {'stream_id': 'c', 'name': 'C', 'num': 1},
        {'stream_id': 'd', 'name': 'D', 'num': 3},
        {'stream_id': 'e', 'name': 'E', 'num': 2},
      ]);
      expect([for (final c in channels) c.id], ['c', 'e', 'a', 'd', 'b']);
    });

    test('réponse qui n’est pas une liste : aucune chaîne', () {
      expect(parseChannels('{}'), isEmpty);
    });
  });

  test('catégories du direct : même décodage que les films', () {
    final categories = parseCategories(
      File('test/fixtures/live_categories.json').readAsStringSync(),
    );
    expect(categories, hasLength(13));
    expect(categories.first.id, '104');
    expect(categories.first.name, 'FRANCE HD');
  });
}
