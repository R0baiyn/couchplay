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
  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(settings),
        accountStoreProvider.overrideWithValue(accounts),
        accountFilesProvider.overrideWithValue(
          AccountFiles(Directory('${support.path}/accounts')),
        ),
      ],
      child: const CouchPlayApp(home: HomeGate()),
    ),
  );
}
