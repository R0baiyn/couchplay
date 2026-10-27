import 'dart:io';

import '../logging.dart';

/// Réponse brute du serveur gardée sur disque, avec sa date.
typedef CachedText = ({String text, DateTime savedAt});

/// Cache du catalogue d'un compte : `accounts/<id>/catalog_<nom>.json`.
///
/// Le texte est gardé tel que le serveur l'a envoyé, sans réencodage. La date
/// est celle du fichier : l'écriture passe par un fichier temporaire renommé
/// (règle 7), donc la date est celle de la dernière écriture complète.
final class CatalogCache {
  const CatalogCache(this.directory);

  final Directory directory;

  static final _validName = RegExp(r'^[A-Za-z0-9_-]+$');

  File _file(String name) {
    // Le nom vient d'ids du serveur (catégories) : jamais de chemin.
    if (!_validName.hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'nom de cache invalide');
    }
    return File('${directory.path}${Platform.pathSeparator}catalog_$name.json');
  }

  Future<CachedText?> read(String name) async {
    final file = _file(name);
    try {
      return (
        text: await file.readAsString(),
        savedAt: await file.lastModified(),
      );
    } on FileSystemException {
      return null;
    }
  }

  /// Écrit [text] ; un échec (disque plein, dossier verrouillé) est loggé
  /// sans interrompre l'affichage : le cache n'est qu'une économie.
  Future<void> write(String name, String text) async {
    final file = _file(name);
    final temp = File('${file.path}.tmp');
    try {
      await directory.create(recursive: true);
      await temp.writeAsString(text, flush: true);
      await temp.rename(file.path);
    } on FileSystemException catch (e) {
      log('Cache du catalogue non écrit', error: e.osError?.errorCode);
    }
  }
}
