import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';

import 'updater.dart';

/// Fin du nom de l'APK publié pour l'architecture [abi], `null` si aucun ne
/// l'est (émulateur x86_64). Un appareil 64 bits qui fait tourner Android en
/// 32 bits (beaucoup de TV) prend l'armv7.
String? androidAssetSuffix(Abi abi) => switch (abi) {
  Abi.androidArm64 => '-android-arm64.apk',
  Abi.androidArm => '-android-armv7.apk',
  _ => null,
};

/// Installation sous Android : l'installateur du système s'ouvre sur l'APK
/// téléchargé, et Android demande une confirmation à chaque fois.
///
/// Remise à plus tard, la mise à jour reste dans [workDir] avec sa version :
/// au démarrage suivant, l'installateur s'ouvre de lui-même. Refusée, elle
/// revient au démarrage d'après. Une fois installée, le dossier est vidé.
final class AndroidInstaller implements Installer {
  AndroidInstaller({required this.assetSuffix, required this.workDir});

  /// Canal de `MainActivity.kt`. Il ne reçoit aucun chemin : l'APK est
  /// toujours `<cache>/update/couchplay.apk`, seul fichier que l'app expose
  /// à l'installateur.
  static const _channel = MethodChannel('couchplay/update');

  @override
  final String assetSuffix;

  /// `<cache>/update` : le dossier que voit `MainActivity.kt`.
  @override
  final Directory workDir;

  @override
  String get later => 'au prochain démarrage de CouchPlay';

  @override
  String get packageName => 'couchplay.apk';

  File get _apk => File('${workDir.path}/$packageName');

  /// Écrite une fois l'APK vérifié : sans elle, le fichier est incomplet.
  File get _version => File('${workDir.path}/version');

  @override
  Future<void> prepared(Update update, File package) =>
      _version.writeAsString(update.version);

  @override
  Future<void> installNow() => _channel.invokeMethod<void>('install');

  @override
  Future<bool> installPending(String current) async {
    final String version;
    try {
      version = await _version.readAsString();
    } on FileSystemException {
      return false;
    }
    if (!isNewer(version, current) || !await _apk.exists()) {
      // Déjà installée, ou effacée avec le cache par Android : place nette.
      await workDir.delete(recursive: true);
      return false;
    }
    await installNow();
    return true;
  }
}
