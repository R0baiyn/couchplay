import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';

import '../logging.dart';
import 'updater.dart';

/// Fin du nom de l'APK publié pour l'architecture [abi], `null` si aucun ne
/// l'est (émulateur x86_64). Un appareil 64 bits qui fait tourner Android en
/// 32 bits (beaucoup de TV) prend l'armv7.
String? androidAssetSuffix(Abi abi) => switch (abi) {
  Abi.androidArm64 => '-android-arm64.apk',
  Abi.androidArm => '-android-armv7.apk',
  _ => null,
};

/// APK à installer d'après les architectures 64 bits de l'appareil
/// (`Build.SUPPORTED_64_BIT_ABIS`) et celle du processus [current] : une app
/// armv7 passe à l'arm64 dès que l'appareil le lit (code de version plus
/// grand, Android accepte le passage). Sinon celui du processus
/// ([androidAssetSuffix]) : armv7 d'une TV 32 bits (liste vide), rien pour
/// un x86_64, même s'il traduit l'arm64 (émulateurs, Chromebooks :
/// `x86_64,arm64-v8a`).
String? androidAssetSuffixFor(List<String> supported64BitAbis, Abi current) =>
    current == Abi.androidArm && supported64BitAbis.contains('arm64-v8a')
    ? androidAssetSuffix(Abi.androidArm64)
    : androidAssetSuffix(current);

/// Installation sous Android : l'installateur du système s'ouvre sur l'APK
/// téléchargé, et Android demande une confirmation à chaque fois.
///
/// Remise à plus tard, la mise à jour reste dans [workDir] avec sa version :
/// au démarrage suivant, l'installateur s'ouvre de lui-même, sauf si la
/// place manque : il attend alors l'accord de l'utilisateur. Refusée, elle
/// revient au démarrage d'après. Une fois installée, le dossier est vidé.
final class AndroidInstaller implements Installer {
  AndroidInstaller({required this.assetSuffix, required this.workDir});

  /// Canal de `MainActivity.kt`. Il ne reçoit aucun chemin : l'APK est
  /// toujours `<cache>/update/couchplay.apk`, seul fichier que l'app expose
  /// à l'installateur.
  static const _channel = MethodChannel('couchplay/update');

  /// APK publié pour cet appareil ([androidAssetSuffixFor]). Canal sans
  /// réponse (ancienne activité, test) : l'architecture du processus seule.
  /// [current] : celle du processus, remplacée dans les tests.
  static Future<String?> deviceAssetSuffix({Abi? current}) async {
    List<String>? abis;
    try {
      abis = await _channel.invokeListMethod<String>('supported64BitAbis');
    } on PlatformException {
      // Liste inconnue : l'architecture du processus décide.
    } on MissingPluginException {
      // Idem.
    }
    return androidAssetSuffixFor(abis ?? const [], current ?? Abi.current());
  }

  @override
  final String assetSuffix;

  @override
  Future<void> Function(Uri page)? get openPage => null;

  /// Android vérifie lui-même la signature de l'APK.
  @override
  bool get signed => false;

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
  Future<void> prepared(Update update, File package, String? sha256) =>
      _version.writeAsString(update.version);

  @override
  Future<void> installNow() async {
    // Le paquet de l'installateur du système qui ouvre l'APK ; vide : aucun
    // trouvé, Android a choisi l'app (D-060).
    final installer = await _channel.invokeMethod<String>('install');
    if (installer == null) return;
    log(
      installer.isEmpty
          ? 'Mise à jour : installateur du système introuvable, choix laissé '
                'à Android'
          : 'Mise à jour : installateur $installer',
    );
  }

  @override
  Future<int?> freeSpace() async {
    try {
      return await _channel.invokeMethod<int>('freeSpace');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> installPending(
    String current, {
    Future<bool> Function(int size)? allow,
  }) async {
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
    // Retenue (place insuffisante) : elle reste là pour plus tard.
    if (allow != null && !await allow(await _apk.length())) return false;
    try {
      await installNow();
    } on PlatformException {
      // Installation impossible (APK refusé, aucun installateur) : place
      // nette, sinon la même erreur reviendrait à chaque démarrage et
      // masquerait les mises à jour suivantes.
      await workDir.delete(recursive: true);
      return false;
    }
    return true;
  }
}
