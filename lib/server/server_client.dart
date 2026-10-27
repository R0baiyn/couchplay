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

final class TooManyRequests extends ServerException {
  const TooManyRequests();

  @override
  String get message =>
      'Trop de tentatives : le serveur bloque, réessaie dans quelques minutes';
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
  // Le code http aide à comprendre un refus inattendu (404, 500…) ; il ne
  // contient jamais d'identifiant.
  String get message => 'Réponse du serveur illisible ($details)';
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
    final body = _tryDecode(await fetch());
    if (body == null) {
      _log('Infos du compte', 'JSON invalide');
      throw const InvalidResponse('JSON invalide');
    }
    final userInfo = asMap(asMap(body)['user_info']);
    // Mauvais identifiants : `auth: 0`, ou parfois une liste vide.
    if (asInt(userInfo['auth']) != 1) throw const CredentialsRejected();
    return AccountInfo.fromJson(userInfo);
  }

  /// Texte brut de la réponse à [action] (rien = infos du compte).
  ///
  /// Le texte n'est pas décodé ici : les grosses listes se décodent hors du
  /// thread de l'interface (règle 5), et partent telles quelles en cache.
  Future<String> fetch([
    String? action,
    Map<String, String> params = const {},
  ]) async {
    final uri = Uri.parse('$host/player_api.php').replace(
      queryParameters: {
        'username': username,
        'password': password,
        'action': ?action,
        ...params,
      },
    );
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
    final text = response.data ?? '';
    if (status == 200) {
      // Identifiants révoqués : certains serveurs répondent 200 avec
      // `{"user_info":{"auth":0}}`, même pour une liste. Sans ce contrôle,
      // l'app mettrait en cache un catalogue vide. Les listes commencent par
      // `[` : seul un petit objet est décodé ici.
      if (text.length < 4096 && text.trimLeft().startsWith('{')) {
        final body = _tryDecode(text);
        final userInfo = body is Map ? body['user_info'] : null;
        if (userInfo != null && asInt(asMap(userInfo)['auth']) != 1) {
          throw const CredentialsRejected();
        }
      }
      return text;
    }

    // Corps d'erreur, petit : décodé ici. Mauvais identifiants : `auth: 0`
    // avec un code d'erreur chez certains serveurs (404). Le contenu prime.
    final body = _tryDecode(text);
    final userInfo = body is Map ? body['user_info'] : null;
    if (userInfo != null && asInt(asMap(userInfo)['auth']) != 1) {
      throw const CredentialsRejected();
    }
    switch (status) {
      case 401:
        throw const CredentialsRejected();
      // Filtrage par User-Agent ou par adresse IP, pas les identifiants.
      case 403:
        throw const AccessDenied();
      // Pare-feu du serveur après trop de requêtes ou d'essais ratés.
      case 429:
        throw const TooManyRequests();
      default:
        _log('GET $uri', 'HTTP $status');
        throw InvalidResponse('HTTP $status');
    }
  }

  static Object? _tryDecode(String? text) {
    try {
      return jsonDecode(text ?? '');
    } on FormatException {
      return null;
    }
  }

  /// Adresse du flux d'un film ou d'un épisode : `/movie/U/P/<id>.<ext>`.
  ///
  /// Les identifiants sont dans le chemin, imposé par le protocole : cette
  /// URL ne doit passer par aucun log sans [redact].
  Uri streamUri(ContentKind kind, String id, String extension) {
    final path = switch (kind) {
      ContentKind.movies => 'movie',
      ContentKind.series => 'series',
    };
    final segments = [
      username,
      password,
      '$id.$extension',
    ].map(Uri.encodeComponent).join('/');
    return Uri.parse('$host/$path/$segments');
  }

  /// Libère les connexions. Le client n'est plus utilisable ensuite.
  void close() => _dio.close(force: true);

  void _log(String message, Object error) =>
      log(message, error: error, secrets: [username, password]);
}
