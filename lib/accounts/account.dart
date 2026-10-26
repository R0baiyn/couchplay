import 'dart:math';

import '../server/json_read.dart';

/// User-Agent proposé à la création d'un compte : celui de VLC, que les
/// serveurs qui filtrent laissent passer.
const defaultUserAgent = 'VLC/3.0.20 LibVLC/3.0.20';

/// Un accès à un serveur, identifiants compris.
///
/// Ne vit qu'en mémoire et dans le stockage sécurisé (règle 1) : jamais dans un
/// log, un fichier en clair ou une réponse d'erreur.
final class Account {
  const Account({
    required this.id,
    required this.name,
    required this.host,
    required this.username,
    required this.password,
    required this.userAgent,
  });

  /// Relit un compte enregistré ; `null` si l'entrée est inutilisable.
  static Account? fromJson(Object? json) {
    final map = asMap(json);
    final id = asId(map['id']);
    final host = asString(map['host']);
    final username = asString(map['username']);
    final password = asString(map['password']);
    if (id == null ||
        !isValidAccountId(id) ||
        host == null ||
        username == null ||
        password == null) {
      return null;
    }
    return Account(
      id: id,
      name: asString(map['name']) ?? host,
      host: host,
      username: username,
      password: password,
      userAgent: asString(map['userAgent']) ?? defaultUserAgent,
    );
  }

  /// Identifiant aléatoire, fixé à la création et jamais recalculé : il nomme
  /// le dossier des données du compte (règle 6).
  static String newId() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  final String id;
  final String name;

  /// `http(s)://hôte[:port]`, normalisé par [normalizeHost].
  final String host;
  final String username;
  final String password;
  final String userAgent;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'username': username,
    'password': password,
    'userAgent': userAgent,
  };

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.id == id &&
      other.name == name &&
      other.host == host &&
      other.username == username &&
      other.password == password &&
      other.userAgent == userAgent;

  @override
  int get hashCode =>
      Object.hash(id, name, host, username, password, userAgent);

  // Les identifiants n'apparaissent pas, même dans un message de débogage.
  @override
  String toString() => 'Account($id, $name)';
}

/// Un id nomme le dossier des données du compte, effacé avec lui : lettres,
/// chiffres, `_` et `-` seulement, jamais de séparateur ni de remontée.
bool isValidAccountId(String id) => _idPattern.hasMatch(id);

final _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');

/// Message d'erreur pour un hôte saisi, ou `null` s'il est valide.
///
/// Attendu : `http://hôte:port` ou `https://hôte`, sans chemin ni paramètres.
String? hostError(String input) {
  final text = input.trim();
  if (text.isEmpty) return 'Indique l\'adresse du serveur';
  final uri = Uri.tryParse(text);
  if (uri == null) return 'Adresse invalide';
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return 'L\'adresse commence par http:// ou https://';
  }
  if (uri.host.isEmpty) return 'Adresse invalide';
  if (uri.userInfo.isNotEmpty) {
    return 'Les identifiants vont dans leurs propres champs';
  }
  if ((uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    return 'Sans chemin : par exemple http://serveur.com:8080';
  }
  return null;
}

/// Forme canonique d'un hôte valide pour [hostError] : schéma en minuscules,
/// sans `/` final.
String normalizeHost(String input) {
  final uri = Uri.parse(input.trim());
  return '${uri.scheme}://${uri.authority}';
}
