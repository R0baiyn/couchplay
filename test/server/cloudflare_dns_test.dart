import 'dart:convert';
import 'dart:io';

import 'package:couchplay/server/cloudflare_dns.dart';
import 'package:flutter_test/flutter_test.dart';

String _answer(List<Map<String, Object>> records) =>
    jsonEncode({'Status': 0, 'Answer': records});

void main() {
  test('alias sautés : première adresse IPv4 et sa durée', () {
    final (address, ttl) = CloudflareDns.parseAnswer(
      _answer([
        {'name': 'a.com', 'type': 5, 'TTL': 30, 'data': 'cdn.a.com.'},
        {'name': 'cdn.a.com', 'type': 1, 'TTL': 120, 'data': '203.0.113.7'},
      ]),
    );
    expect(address.address, '203.0.113.7');
    expect(ttl, 120);
    expect(
      () => CloudflareDns.parseAnswer(jsonEncode({'Status': 3})),
      throwsFormatException,
    );
  });

  test('1.1.1.1 d\'abord, 1.0.0.1 en secours, puis gardé en cache', () async {
    final asked = <String>[];
    final dns = CloudflareDns(
      query: (server, host) async {
        asked.add(server);
        if (server == '1.1.1.1') throw const SocketException('bloqué');
        return _answer([
          {'type': 1, 'TTL': 300, 'data': '203.0.113.7'},
        ]);
      },
    );
    expect((await dns.lookup('serveur.com')).address, '203.0.113.7');
    expect((await dns.lookup('serveur.com')).address, '203.0.113.7');
    expect(asked, ['1.1.1.1', '1.0.0.1']);
  });

  test('sans réponse de Cloudflare : échec, pas de DNS du système', () async {
    final dns = CloudflareDns(
      query: (_, _) async => throw const SocketException('hors ligne'),
    );
    await expectLater(
      dns.lookup('serveur.com'),
      throwsA(isA<SocketException>()),
    );
  });

  test('une adresse IP ou localhost ne demande rien', () async {
    final dns = CloudflareDns(query: (_, _) async => fail('aucune requête'));
    expect((await dns.lookup('192.168.1.42')).address, '192.168.1.42');
    expect((await dns.lookup('localhost')).isLoopback, isTrue);
  });
}
