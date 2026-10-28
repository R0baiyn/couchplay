import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'accounts/account_files.dart';
import 'accounts/account_store.dart';
import 'app.dart';
import 'server/cloudflare_dns.dart';
import 'settings/settings.dart';
import 'update/android_installer.dart';
import 'update/updater.dart';
import 'update/windows_installer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Toutes les connexions HTTP de l'app résolvent les noms par Cloudflare.
  HttpOverrides.global = CloudflareHttpOverrides();
  MediaKit.ensureInitialized();
  final (settings, accounts, support, package, installer) = await (
    SettingsStore.open(),
    AccountStore.open(),
    getApplicationSupportDirectory(),
    PackageInfo.fromPlatform(),
    _installer(),
  ).wait;
  final files = AccountFiles(Directory('${support.path}/accounts'));
  // En tâche de fond : ne retarde pas le premier rendu.
  unawaited(files.sync({for (final a in accounts.current.accounts) a.id}));
  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(settings),
        accountStoreProvider.overrideWithValue(accounts),
        accountFilesProvider.overrideWithValue(files),
        appVersionProvider.overrideWithValue(package.version),
        if (installer != null)
          updaterProvider.overrideWithValue(
            Updater(version: package.version, installer: installer),
          ),
      ],
      child: const CouchPlayApp(home: HomeGate()),
    ),
  );
}

/// L'installation des mises à jour, pour une version release qui a un
/// fichier publié : installée ou portable sous Windows, APK de son
/// architecture sous Android.
Future<Installer?> _installer() async {
  if (!kReleaseMode) return null;
  if (Platform.isWindows) {
    return WindowsInstaller.forApp(File(Platform.resolvedExecutable).parent);
  }
  if (Platform.isAndroid) {
    final suffix = androidAssetSuffix(Abi.current());
    if (suffix == null) return null;
    final cache = await getTemporaryDirectory();
    return AndroidInstaller(
      assetSuffix: suffix,
      workDir: Directory('${cache.path}/update'),
    );
  }
  return null;
}
