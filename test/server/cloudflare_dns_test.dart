import 'dart:async';
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

  test('requêtes simultanées pour un même nom : une seule question', () async {
    final answer = Completer<String>();
    var asked = 0;
    final dns = CloudflareDns(
      query: (_, _) {
        asked++;
        return answer.future;
      },
    );
    final first = dns.lookup('serveur.com');
    final second = dns.lookup('serveur.com');
    answer.complete(
      _answer([
        {'type': 1, 'TTL': 300, 'data': '203.0.113.7'},
      ]),
    );
    expect((await first).address, '203.0.113.7');
    expect((await second).address, '203.0.113.7');
    expect(asked, 1);
  });

  test("un échec n'est pas gardé : la demande suivante repart", () async {
    var asked = 0;
    final dns = CloudflareDns(
      query: (_, _) async {
        asked++;
        throw const SocketException('hors ligne');
      },
    );
    await expectLater(dns.lookup('a.com'), throwsA(isA<SocketException>()));
    await expectLater(dns.lookup('a.com'), throwsA(isA<SocketException>()));
    // Deux serveurs essayés par demande.
    expect(asked, 4);
  });

  group('resolveForPlayer', () {
    test('HTTPS ou adresse IP : URL inchangée, sans en-tête Host', () async {
      for (final url in [
        'https://serveur.com/a.mkv',
        'http://192.0.2.7:80/a',
      ]) {
        final (resolved, headers) = await resolveForPlayer(Uri.parse(url));
        expect(resolved, Uri.parse(url));
        expect(headers, isEmpty);
      }
    });

    test("HTTP : adresse résolue dans l'URL, Host avec le port", () async {
      // `localhost` est résolu sans requête : pas de réseau dans ce test.
      final (resolved, headers) = await resolveForPlayer(
        Uri.parse('http://localhost:8080/movie/a.mkv'),
      );
      expect(resolved, Uri.parse('http://127.0.0.1:8080/movie/a.mkv'));
      expect(headers, {'Host': 'localhost:8080'});

      final (_, noPort) = await resolveForPlayer(
        Uri.parse('http://localhost/a.mkv'),
      );
      expect(noPort, {'Host': 'localhost'});
    });
  });

  // Vraies requêtes à Cloudflare : lancées seulement avec RESEAU=1
  // (`RESEAU=1 flutter test test/server/cloudflare_dns_test.dart`).
  group('réseau', skip: Platform.environment['RESEAU'] != '1', () {
    for (final server in ['1.1.1.1', '1.0.0.1']) {
      test(
        '$server : sans racines du système, la racine embarquée suffit',
        () async {
          final body = await CloudflareDns.https(
            server,
            'example.com',
            CloudflareDns.dohContext(withTrustedRoots: false),
          );
          expect(
            CloudflareDns.parseAnswer(body).$1.type,
            InternetAddressType.IPv4,
          );
        },
      );

      test(
        '$server : contexte de l\'app (système + racine embarquée)',
        () async {
          final body = await CloudflareDns.https(server, 'example.com');
          expect(
            CloudflareDns.parseAnswer(body).$1.type,
            InternetAddressType.IPv4,
          );
        },
      );

      test('$server : sans aucune racine, le certificat est refusé', () async {
        await expectLater(
          CloudflareDns.https(
            server,
            'example.com',
            SecurityContext(withTrustedRoots: false),
          ),
          throwsA(isA<HandshakeException>()),
        );
      });
    }
  });
}
