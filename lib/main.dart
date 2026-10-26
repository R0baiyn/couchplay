import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'accounts/account_store.dart';
import 'app.dart';
import 'settings/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final (settings, accounts) = await (
    SettingsStore.open(),
    AccountStore.open(),
  ).wait;
  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(settings),
        accountStoreProvider.overrideWithValue(accounts),
      ],
      child: const CouchPlayApp(home: HomeGate()),
    ),
  );
}
