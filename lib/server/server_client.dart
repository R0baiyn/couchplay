import 'dart:convert';

import 'package:dio/dio.dart';

import '../logging.dart';
import 'json_read.dart';
import 'models.dart';

/// Échec d'un appel au serveur, avec un message prêt à afficher.
sealed class ServerException implements Exception {
  const ServerException();

  String get message;

  @override
  String toString() => message;
}

final class CredentialsRejected extends ServerException {
  const CredentialsRejected();

  @override
  String get message => 'Identifiants refusés';
}

final class AccessDenied extends ServerException {
  const AccessDenied();

  @override
  String get message =>
      'Accès refusé par le serveur : essaie un autre User-Agent';
}

final class ServerUnreachable extends ServerException {
  const ServerUnreachable();

  @override
  String get message => 'Serveur injoignable';
}

final class ServerTimeout extends ServerException {
  const ServerTimeout();

  @override
  String get message => 'Le serveur ne répond pas';
}

final class InvalidResponse extends ServerException {
  const InvalidResponse(this.details);

  /// Pour les logs : code HTTP ou nature du problème.
  final String details;

  @override
  String get message => 'Réponse du serveur illisible';
}

/// Appels à l'API du serveur pour un compte.
///
/// Les identifiants voyagent dans l'URL, imposé par le protocole : toute URL
/// loggée passe par [log], qui les masque.
final class ServerClient {
  ServerClient({
    required this.host,
    required this.username,
    required this.password,
    required String userAgent,
    HttpClientAdapter? adapter,
  }) : _dio = Dio(
         BaseOptions(
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 30),
           headers: {'User-Agent': userAgent},
           // Texte brut : certains serveurs annoncent du HTML pour du JSON.
           responseType: ResponseType.plain,
           // Les codes d'erreur sont traduits plus bas, pas par dio.
           validateStatus: (_) => true,
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  /// `http(s)://hôte:port`, sans `/` final.
  final String host;
  final String username;
  final String password;
  final Dio _dio;

  /// Vérifie les identifiants et renvoie l'état de l'abonnement.
  Future<AccountInfo> accountInfo() async {
    final userInfo = asMap(asMap(await _get())['user_info']);
    // Mauvais identifiants : `auth: 0`, ou parfois une liste vide.
    if (asInt(userInfo['auth']) != 1) throw const CredentialsRejected();
    return AccountInfo.fromJson(userInfo);
  }

  Uri _apiUri(String? action) => Uri.parse('$host/player_api.php').replace(
    queryParameters: {
      'username': username,
      'password': password,
      'action': ?action,
    },
  );

  Future<Object?> _get([String? action]) async {
    final uri = _apiUri(action);
    final Response<String> response;
    try {
      response = await _dio.getUri<String>(uri);
    } on DioException catch (e) {
      // Seulement le type : le message de dio recopie l'URL complète.
      _log('Échec GET $uri', e.type);
      throw switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => const ServerTimeout(),
        _ => const ServerUnreachable(),
      };
    }

    final status = response.statusCode ?? 0;
    // Les mauvais identifiants arrivent en général en 200 avec `auth: 0`.
    if (status == 401) throw const CredentialsRejected();
    // 403 : filtrage par User-Agent ou par adresse IP, pas les identifiants.
    if (status == 403) throw const AccessDenied();
    if (status != 200) {
      _log('GET $uri', 'HTTP $status');
      throw InvalidResponse('HTTP $status');
    }
    try {
      return jsonDecode(response.data ?? '');
    } on FormatException {
      _log('GET $uri', 'JSON invalide');
      throw const InvalidResponse('JSON invalide');
    }
  }

  /// Libère les connexions. Le client n'est plus utilisable ensuite.
  void close() => _dio.close(force: true);

  void _log(String message, Object error) =>
      log(message, error: error, secrets: [username, password]);
}
