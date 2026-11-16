import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Racine des vidéos téléchargées, `<base>/downloads`, un dossier par compte
/// dessous. Des fichiers de plusieurs Go : sous Windows, `%LOCALAPPDATA%`
/// (`getApplicationCacheDirectory`, que Windows ne vide pas) plutôt que le
/// profil itinérant de [support] ; ailleurs, [support] lui-même (Android :
/// `filesDir`, propre à l'app, sans permission, jamais purgé, exclu des
/// sauvegardes ; le dossier de cache, lui, peut être vidé par le système).
Future<Directory> downloadsRoot(Directory support) async {
  final base = Platform.isWindows
      ? await getApplicationCacheDirectory()
      : support;
  return Directory('${base.path}${Platform.pathSeparator}downloads');
}
