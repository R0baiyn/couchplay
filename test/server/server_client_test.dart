import 'dart:io';
import 'dart:typed_data';

import 'package:couchplay/server/server_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Répond à la place du réseau et garde la dernière requête.
final class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._respond);

  final Future<ResponseBody> Function(RequestOptions options) _respond;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    last = options;
    return _respond(options);
  }

  @override
  void close({bool force = false}) {}
}

_FakeAdapter _replying(String body, {int status = 200}) =>
    _FakeAdapter((_) async => ResponseBody.fromString(body, status));

_FakeAdapter _failing(DioExceptionType type) => _FakeAdapter(
  (options) async => throw DioException(requestOptions: options, type: type),
);

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
    final info = await _client(_replying(body)).accountInfo();

    expect(info.status, 'Active');
    expect(info.isActive, isTrue);
    expect(info.isTrial, isFalse);
    expect(info.maxConnections, 1);
    expect(info.activeConnections, 0);
    // exp_date de la fixture : "1823879381", en secondes.
    expect(info.expiresAt, DateTime.utc(2027, 10, 18, 17, 9, 41));
  });

  test('encode les identifiants et envoie le User-Agent', () async {
    final adapter = _replying('{"user_info":{"auth":1,"status":"Active"}}');
    await _client(adapter).accountInfo();

    final request = adapter.last!;
    expect(request.uri.path, '/player_api.php');
    expect(request.uri.queryParameters, {'username': _user, 'password': _pass});
    expect(request.headers['User-Agent'], 'TestAgent/1.0');
  });

  test('un abonnement sans date d\'expiration n\'expire pas', () async {
    final info = await _client(
      _replying(
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
        await errorOf(_replying('{"user_info":{"auth":0}}')),
        isA<CredentialsRejected>(),
      );
    });

    test('liste vide ou HTTP 401 : identifiants refusés', () async {
      expect(await errorOf(_replying('[]')), isA<CredentialsRejected>());
      expect(
        await errorOf(_replying('', status: 401)),
        isA<CredentialsRejected>(),
      );
    });

    test('panne réseau : serveur injoignable', () async {
      expect(
        await errorOf(_failing(DioExceptionType.connectionError)),
        isA<ServerUnreachable>(),
      );
    });

    test('timeout : le serveur ne répond pas', () async {
      expect(
        await errorOf(_failing(DioExceptionType.connectionTimeout)),
        isA<ServerTimeout>(),
      );
      expect(
        await errorOf(_failing(DioExceptionType.receiveTimeout)),
        isA<ServerTimeout>(),
      );
    });

    test('page HTML ou HTTP 500 : réponse illisible', () async {
      expect(
        await errorOf(_replying('<html>maintenance</html>')),
        isA<InvalidResponse>(),
      );
      expect(
        await errorOf(_replying('{}', status: 500)),
        isA<InvalidResponse>(),
      );
    });
  });
}
