import 'dart:io';

import 'package:couchplay/server/server_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

// Avec & et # : ils doivent être encodés dans l'URL.
const _user = 'jean dupont';
const _pass = 'p&ss#1';

ServerClient _client(HttpClientAdapter adapter) => ServerClient(
  host: 'http://example.com:80',
  username: _user,
  password: _pass,
  userAgent: 'TestAgent/1.0',
  adapter: adapter,
);

void main() {
  test('lit l\'état du compte depuis la fixture', () async {
    final body = File('test/fixtures/account.json').readAsStringSync();
    final info = await _client(FakeAdapter.replying(body)).accountInfo();

    expect(info.status, 'Active');
    expect(info.isActive, isTrue);
    expect(info.isTrial, isFalse);
    expect(info.maxConnections, 1);
    expect(info.activeConnections, 0);
    // exp_date de la fixture : "1823879381", en secondes.
    expect(info.expiresAt, DateTime.utc(2027, 10, 18, 17, 9, 41));
  });

  test('encode les identifiants et envoie le User-Agent', () async {
    final adapter = FakeAdapter.replying(
      '{"user_info":{"auth":1,"status":"Active"}}',
    );
    await _client(adapter).accountInfo();

    final request = adapter.last!;
    expect(request.uri.path, '/player_api.php');
    expect(request.uri.queryParameters, {'username': _user, 'password': _pass});
    expect(request.headers['User-Agent'], 'TestAgent/1.0');
  });

  test('un abonnement sans date d\'expiration n\'expire pas', () async {
    final info = await _client(
      FakeAdapter.replying(
        '{"user_info":{"auth":"1","status":"Expired","exp_date":null}}',
      ),
    ).accountInfo();

    expect(info.expiresAt, isNull);
    expect(info.isActive, isFalse);
  });

  group('erreurs typées', () {
    Future<Object?> errorOf(HttpClientAdapter adapter) async {
      try {
        await _client(adapter).accountInfo();
        return null;
      } on ServerException catch (e) {
        return e;
      }
    }

    test('auth à 0 : identifiants refusés', () async {
      expect(
        await errorOf(FakeAdapter.replying('{"user_info":{"auth":0}}')),
        isA<CredentialsRejected>(),
      );
    });

    test('liste vide ou HTTP 401 : identifiants refusés', () async {
      expect(
        await errorOf(FakeAdapter.replying('[]')),
        isA<CredentialsRejected>(),
      );
      expect(
        await errorOf(FakeAdapter.replying('', status: 401)),
        isA<CredentialsRejected>(),
      );
    });

    test('panne réseau : serveur injoignable', () async {
      expect(
        await errorOf(FakeAdapter.failing(DioExceptionType.connectionError)),
        isA<ServerUnreachable>(),
      );
    });

    test('timeout : le serveur ne répond pas', () async {
      expect(
        await errorOf(FakeAdapter.failing(DioExceptionType.connectionTimeout)),
        isA<ServerTimeout>(),
      );
      expect(
        await errorOf(FakeAdapter.failing(DioExceptionType.receiveTimeout)),
        isA<ServerTimeout>(),
      );
    });

    test('page HTML ou HTTP 500 : réponse illisible', () async {
      expect(
        await errorOf(FakeAdapter.replying('<html>maintenance</html>')),
        isA<InvalidResponse>(),
      );
      expect(
        await errorOf(FakeAdapter.replying('{}', status: 500)),
        isA<InvalidResponse>(),
      );
    });
  });

  test('403 : accès refusé, pas identifiants refusés', () async {
    await expectLater(
      _client(FakeAdapter.replying('', status: 403)).accountInfo(),
      throwsA(isA<AccessDenied>()),
    );
  });

  test('les logs d\'erreur ne contiennent pas les identifiants', () async {
    final lines = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add('$message');
    addTearDown(() => debugPrint = original);

    for (final adapter in [
      FakeAdapter.failing(DioExceptionType.connectionError),
      FakeAdapter.replying('<html>', status: 200),
      FakeAdapter.replying('', status: 500),
    ]) {
      await expectLater(_client(adapter).accountInfo(), throwsA(anything));
    }

    expect(lines, hasLength(3));
    for (final line in lines) {
      for (final secret in [
        _user,
        _pass,
        Uri.encodeQueryComponent(_user),
        Uri.encodeQueryComponent(_pass),
      ]) {
        expect(line, isNot(contains(secret)), reason: line);
      }
    }
  });
}
