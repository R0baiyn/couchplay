import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'accounts/account_files.dart';
import 'accounts/account_store.dart';
import 'accounts/app_settings.dart';
import 'app.dart';
import 'downloads/downloads.dart';
import 'downloads/downloads_folder.dart';
import 'logging.dart';
import 'server/cloudflare_dns.dart';
import 'television.dart';
import 'update/android_installer.dart';
import 'update/linux_installer.dart';
import 'update/updater.dart';
import 'update/windows_installer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Erreurs non rattrapées vers le journal (D-058) ; l'affichage de Flutter
  // et le traitement par défaut du moteur restent inchangés. Ici et non dans
  // `startApp` : les essais de bout en bout gardent les leurs.
  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    log(
      'Erreur Flutter',
      error: details.exceptionAsString(),
      stack: details.stack,
    );
    presentError?.call(details);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    log('Erreur non rattrapée', error: error, stack: stack);
    return false;
  };
  // Toutes les connexions HTTP de l'app résolvent les noms par Cloudflare.
  HttpOverrides.global = CloudflareHttpOverrides();
  MediaKit.ensureInitialized();
  final (accounts, support, package, installer, television) = await (
    AccountStore.open(),
    getApplicationSupportDirectory(),
    PackageInfo.fromPlatform(),
    _installer(),
    isTelevision(),
  ).wait;
  startApp(
    accounts: accounts,
    support: support,
    downloads: await downloadsRoot(support),
    version: package.version,
    television: television,
    updater: installer == null
        ? null
        : Updater(version: package.version, installer: installer),
  );
}

/// Câble l'app sur ces comptes et ces dossiers, puis l'affiche. Ne lit aucun
/// dossier du système : les essais de bout en bout la lancent sur des
/// dossiers temporaires et un coffre simulé.
ProviderContainer startApp({
  required AccountStore accounts,
  required Directory support,
  required Directory downloads,
  required String version,
  required bool television,
  Updater? updater,
}) {
  openJournal(File('${support.path}${Platform.pathSeparator}couchplay.log'));
  log(startLine(version: version, television: television));
  final files = AccountFiles(Directory('${support.path}/accounts'));
  final videos = AccountFiles(downloads);
  // En tâche de fond : ne retarde pas le premier rendu.
  unawaited(syncAccountFolders(accounts, files, videos));
  final container = ProviderContainer(
    overrides: [
      accountStoreProvider.overrideWithValue(accounts),
      accountFilesProvider.overrideWithValue(files),
      downloadFilesProvider.overrideWithValue(videos),
      appSettingsFileProvider.overrideWithValue(
        File('${support.path}${Platform.pathSeparator}settings.json'),
      ),
      appVersionProvider.overrideWithValue(version),
      televisionProvider.overrideWithValue(television),
      if (updater != null) updaterProvider.overrideWithValue(updater),
    ],
  );
  // Écoutée dès le démarrage : un téléchargement interrompu reprend, et la
  // file suit le compte actif sans attendre son écran.
  container.listen(downloadsProvider, (_, _) {});
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CouchPlayApp(home: HomeGate()),
    ),
  );
  return container;
}

/// L'installation des mises à jour, pour une version release qui a un
/// fichier publié : installée ou portable sous Windows, APK de son
/// architecture sous Android, simple avis sous Linux.
Future<Installer?> _installer() async {
  if (!kReleaseMode) return null;
  if (Platform.isWindows) {
    return WindowsInstaller.forApp(File(Platform.resolvedExecutable).parent);
  }
  if (Platform.isAndroid) {
    final suffix = await AndroidInstaller.deviceAssetSuffix();
    if (suffix == null) return null;
    final cache = await getTemporaryDirectory();
    return AndroidInstaller(
      assetSuffix: suffix,
      workDir: Directory('${cache.path}/update'),
    );
  }
  if (Platform.isLinux) return LinuxInstaller();
  return null;
}
