import 'dart:io';

import '../logging.dart';

/// Cache du catalogue d'un compte : `accounts/<id>/catalog/<nom>.json`.
///
/// Le texte est gardé tel que le serveur l'a envoyé, sans réencodage ; sa
/// date est celle du fichier. La lecture et l'écriture des gros fichiers se
/// font dans l'isolate de décodage ([readText], [writeText]) : ici, seuls les
/// chemins et les dates.
///
/// Le cache est lié au serveur : si l'adresse ou l'utilisateur du compte
/// change, l'ancien catalogue est effacé au premier accès.
final class CatalogCache {
  CatalogCache(this.directory, {required this.serverKey});

  final Directory directory;

  /// Empreinte de l'adresse et de l'utilisateur du compte ([serverKeyOf]).
  final String serverKey;

  Future<void>? _ready;

  static final _validName = RegExp(r'^[A-Za-z0-9_-]+$');

  /// Fichier du cache [name], ou `null` si le nom (fait d'ids du serveur)
  /// n'est pas sûr comme nom de fichier : on se passe alors de cache.
  String? path(String name) => _validName.hasMatch(name)
      ? '${directory.path}${Platform.pathSeparator}$name.json'
      : null;

  Future<DateTime?> savedAt(String path) async {
    await _ensureServer();
    try {
      return await File(path).lastModified();
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _ensureServer() => _ready ??= _checkServer();

  Future<void> _checkServer() async {
    final marker = File('${directory.path}${Platform.pathSeparator}server');
    try {
      if (await marker.exists() && await marker.readAsString() == serverKey) {
        return;
      }
      if (await directory.exists()) await directory.delete(recursive: true);
      // Sans `recursive` : si le dossier du compte n'existe plus (compte
      // supprimé), on n'écrit rien et le cache reste désactivé.
      await directory.create();
      await marker.writeAsString(serverKey);
    } on FileSystemException catch (e) {
      log('Cache du catalogue non vérifié', error: e.osError?.errorCode);
    }
  }
}

/// Empreinte stable (FNV-1a 32 bits) de l'accès d'un compte : change si
/// l'adresse ou l'utilisateur change. Ce n'est pas un secret, juste un repère.
String serverKeyOf(String host, String username) {
  var hash = 0x811c9dc5;
  for (final unit in '$host|$username'.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Lit un fichier du cache ; `null` s'il manque. Appelé dans un isolate.
String? readText(String path) {
  try {
    return File(path).readAsStringSync();
  } on FileSystemException {
    return null;
  }
}

/// Écrit un fichier du cache, de façon atomique : fichier temporaire au nom
/// unique, puis renommage. Renvoie `false` en cas d'échec (disque plein,
/// fichier verrouillé), sans lever : le cache n'est qu'une économie.
/// Appelé dans un isolate.
bool writeText(String path, String text) {
  final temp = File('$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
  try {
    // Le dossier n'est pas recréé : s'il a disparu, le compte vient d'être
    // supprimé, et une écriture en retard ne doit pas le faire revenir.
    temp.writeAsStringSync(text, flush: true);
    temp.renameSync(path);
    return true;
  } on FileSystemException {
    try {
      if (temp.existsSync()) temp.deleteSync();
    } on FileSystemException {
      // Rien de plus à faire : le fichier temporaire sera écrasé plus tard.
    }
    return false;
  }
}
