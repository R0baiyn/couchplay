import 'package:flutter/foundation.dart';

// Les URL du serveur portent les identifiants en clair : dans la query string
// (`username=<user>&password=<pass>`) et dans le chemin des flux
// (`/movie/<user>/<pass>/42.mkv`).
// Tout texte destiné aux logs passe par [redact].

const _mask = '***';
const _segment = r'''[^/\s?#"']+''';

final _queryCredentials = RegExp(
  r'''((?:[?&]|\\u0026)(?:username|password)=)[^&#\s"']*''',
  caseSensitive: false,
);
final _userInfo = RegExp(
  r'''(\b[a-z][a-z0-9+.-]*://)[^/\s:@"']+:[^/\s@"']+@''',
  caseSensitive: false,
);
final _streamPath = RegExp(
  '(/(?:movie|series|live|timeshift)/)$_segment/$_segment(?=/)',
);
// Direct sans préfixe : http://hôte:port/U/P/42 ou /42.ts
final _shortLivePath = RegExp(
  '(://$_segment/)$_segment/$_segment'
  r'''(?=/\d+(?:\.\w+)?(?:$|[\s?#"'/]))''',
);

/// Remplace les identifiants présents dans [text] par `***`.
///
/// [secrets] ajoute une seconde couche : ces valeurs, brutes ou encodées en URL,
/// sont masquées partout, même hors d'une URL. Les valeurs de moins de 3
/// caractères sont ignorées, sans quoi elles masqueraient tout le texte.
String redact(String text, {Iterable<String> secrets = const []}) {
  var result = text
      .replaceAllMapped(_queryCredentials, (m) => '${m[1]}$_mask')
      .replaceAllMapped(_userInfo, (m) => '${m[1]}$_mask:$_mask@')
      .replaceAllMapped(_streamPath, (m) => '${m[1]}$_mask/$_mask')
      .replaceAllMapped(_shortLivePath, (m) => '${m[1]}$_mask/$_mask');

  final variants = <String>{
    for (final secret in secrets)
      if (secret.trim().length >= 3) ...[
        secret,
        Uri.encodeComponent(secret),
        Uri.encodeQueryComponent(secret),
      ],
  }.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final variant in variants) {
    result = result.replaceAll(variant, _mask);
  }
  return result;
}

/// Écrit [message] dans la console, identifiants masqués.
///
/// Rien n'est écrit en release : aucun risque de fuite et aucun coût.
void log(String message, {Object? error, Iterable<String> secrets = const []}) {
  if (!kDebugMode) return;
  final text = error == null ? message : '$message : $error';
  debugPrint('[CouchPlay] ${redact(text, secrets: secrets)}');
}
