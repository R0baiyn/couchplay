import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'accounts/account_files.dart';
import 'accounts/account_store.dart';
import 'app.dart';
import 'settings/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final (settings, accounts, support) = await (
    SettingsStore.open(),
    AccountStore.open(),
    getApplicationSupportDirectory(),
  ).wait;
  final files = AccountFiles(Directory('${support.path}/accounts'));
  // En tâche de fond : ne retarde pas le premier rendu.
  unawaited(
    files.removeOrphans({for (final a in accounts.current.accounts) a.id}),
  );
  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(settings),
        accountStoreProvider.overrideWithValue(accounts),
        accountFilesProvider.overrideWithValue(files),
      ],
      child: const CouchPlayApp(home: HomeGate()),
    ),
  );
}
