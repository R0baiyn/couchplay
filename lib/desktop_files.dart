import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ouvrir un dossier (vidéos, journal) et exporter une vidéo : sur
/// ordinateur seulement (D-043). Android et Android TV n'ont ni l'un ni
/// l'autre.
final desktopFilesProvider = Provider<bool>(
  (ref) => Platform.isWindows || Platform.isLinux,
);

/// Ouvre [folder] dans l'explorateur de fichiers, en le créant s'il manque.
/// Surchargé dans les tests.
final openFolderProvider = Provider<Future<void> Function(Directory)>(
  (ref) => openFolder,
);

/// Une app graphique, pas un processus caché : `explorer.exe` rend souvent
/// un code de sortie non nul même quand la fenêtre s'ouvre, d'où `detached`
/// (le code n'est jamais lu).
Future<void> openFolder(Directory folder) async {
  await folder.create(recursive: true);
  await Process.start(Platform.isWindows ? 'explorer.exe' : 'xdg-open', [
    folder.path,
  ], mode: ProcessStartMode.detached);
}
