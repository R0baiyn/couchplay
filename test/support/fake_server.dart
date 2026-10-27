import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Répond à la place du réseau, compte les requêtes et garde la dernière.
final class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this._respond);

  /// Renvoie [body] avec le code [status] à chaque requête.
  FakeAdapter.replying(String body, {int status = 200})
    : this((_) async => ResponseBody.fromString(body, status));

  /// Échoue à chaque requête comme dio le ferait, avec le type [type].
  FakeAdapter.failing(DioExceptionType type)
    : this(
        (options) async =>
            throw DioException(requestOptions: options, type: type),
      );

  /// Répond selon le paramètre `action` de la requête (`''` pour les infos
  /// du compte) ; une action absente de [bodies] donne un 404.
  FakeAdapter.routes(Map<String, String> bodies)
    : this((options) async {
        final body = bodies[options.uri.queryParameters['action'] ?? ''];
        return body == null
            ? ResponseBody.fromString('', 404)
            : ResponseBody.fromString(body, 200);
      });

  final Future<ResponseBody> Function(RequestOptions options) _respond;
  RequestOptions? last;
  var calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    last = options;
    calls++;
    return _respond(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Réponse d'un compte actif, pour les tests qui n'en étudient pas le détail.
const activeAccountJson =
    '{"user_info":{"auth":1,"status":"Active","exp_date":null,'
    '"max_connections":"1","active_cons":"0"}}';
