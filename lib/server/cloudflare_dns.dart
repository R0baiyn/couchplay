import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../logging.dart';

/// Résout les noms d'hôte par Cloudflare (1.1.1.1, puis 1.0.0.1 en secours),
/// en DNS sur HTTPS : jamais par le DNS du système ni du fournisseur
/// d'accès, qui peut bloquer ou détourner certains noms. Pas de repli sur le
/// DNS du système : si Cloudflare ne répond pas, la connexion échoue.
final class CloudflareDns {
  CloudflareDns({Future<String> Function(String server, String host)? query})
    : _query = query ?? _https;

  static const servers = ['1.1.1.1', '1.0.0.1'];
  static const _service = 'cloudflare-dns.com';

  final Future<String> Function(String server, String host) _query;
  final _cache = <String, ({InternetAddress address, DateTime until})>{};
  final _pending = <String, Future<InternetAddress>>{};

  /// Adresse IPv4 de [host]. Une adresse IP est rendue telle quelle.
  Future<InternetAddress> lookup(String host) {
    if (InternetAddress.tryParse(host) case final address?) {
      return Future.value(address);
    }
    if (host == 'localhost') return Future.value(InternetAddress.loopbackIPv4);
    final cached = _cache[host];
    if (cached != null && DateTime.now().isBefore(cached.until)) {
      return Future.value(cached.address);
    }
    // Plusieurs connexions simultanées : une seule requête.
    // Accolades : rendre la valeur retirée ferait attendre la requête par
    // elle-même.
    return _pending[host] ??= _resolve(host).whenComplete(() {
      _pending.remove(host);
    });
  }

  Future<InternetAddress> _resolve(String host) async {
    for (final server in servers) {
      try {
        final (address, ttl) = parseAnswer(await _query(server, host));
        _cache[host] = (
          address: address,
          until: DateTime.now().add(Duration(seconds: ttl.clamp(60, 3600))),
        );
        return address;
      } on Exception catch (e) {
        log('DNS Cloudflare $server : $host', error: e.runtimeType);
      }
    }
    throw SocketException('Nom introuvable par Cloudflare : $host');
  }

  /// Première adresse IPv4 d'une réponse JSON de Cloudflare, et sa durée de
  /// validité en secondes. Les alias (CNAME) qui la précèdent sont sautés.
  static (InternetAddress, int) parseAnswer(String body) {
    final json = jsonDecode(body);
    if (json is Map && json['Answer'] is List) {
      for (final record in json['Answer'] as List) {
        if (record is Map && record['type'] == 1 && record['data'] is String) {
          final address = InternetAddress.tryParse(record['data'] as String);
          if (address != null) {
            final ttl = record['TTL'];
            return (address, ttl is int ? ttl : 300);
          }
        }
      }
    }
    throw const FormatException('Aucune adresse IPv4 dans la réponse');
  }

  static Future<String> _https(String server, String host) async {
    // Connexion directe à [server], certificat vérifié pour le nom du
    // service : Dart refuse les certificats présentés pour une adresse IP.
    // ponytail: sous Windows, la racine SSL.com de ce certificat n'est dans
    // le magasin système qu'après un premier téléchargement par Windows ;
    // l'embarquer dans l'app si un PC neuf échoue ici.
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..connectionFactory = (uri, _, _) async {
        final task = await Socket.startConnect(server, 443);
        return ConnectionTask.fromSocket(
          task.socket.then((s) => SecureSocket.secure(s, host: _service)),
          task.cancel,
        );
      };
    try {
      final request = await client.getUrl(
        Uri.https(_service, '/dns-query', {'name': host, 'type': 'A'}),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }
}

/// Le résolveur de l'app.
final cloudflareDns = CloudflareDns();

/// Fait passer tous les clients HTTP de l'app (API du serveur, affiches)
/// par [cloudflareDns] : la connexion se fait à l'adresse résolue, le nom
/// reste celui de l'URL (en-tête Host, vérification du certificat HTTPS).
final class CloudflareHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (uri, proxyHost, proxyPort) async {
          final address = await cloudflareDns.lookup(uri.host);
          final task = await Socket.startConnect(address, uri.port);
          if (uri.scheme != 'https') return task;
          return ConnectionTask.fromSocket(
            task.socket.then(
              (socket) =>
                  SecureSocket.secure(socket, host: uri.host, context: context),
            ),
            task.cancel,
          );
        };
}

/// [url] avec l'adresse résolue par Cloudflare à la place du nom, et
/// l'en-tête Host à garder : pour le lecteur (mpv), qui a son propre
/// résolveur. En HTTPS, l'URL reste telle quelle (certificat au nom de
/// l'hôte).
///
/// `ponytail:` une redirection du serveur vers un autre hôte est suivie par
/// mpv avec le DNS du système ; à traiter si un fournisseur redirige les
/// flux vers un nom bloqué.
Future<(Uri, Map<String, String>)> resolveForPlayer(Uri url) async {
  if (url.scheme != 'http' || InternetAddress.tryParse(url.host) != null) {
    return (url, const <String, String>{});
  }
  final address = await cloudflareDns.lookup(url.host);
  final host = url.hasPort ? '${url.host}:${url.port}' : url.host;
  return (url.replace(host: address.address), {'Host': host});
}
