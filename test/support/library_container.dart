import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Conteneur d'un compte actif dans un dossier temporaire : de quoi lire et
/// écrire sa bibliothèque, sans serveur.
Future<ProviderContainer> libraryContainer(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  final root = Directory.systemTemp.createTempSync('couchplay_library_');
  addTearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Écriture encore en cours sous Windows : le dossier reste, sans effet.
    }
  });
  FlutterSecureStorage.setMockInitialValues({});
  final (store, files) = (await tester.runAsync(() async {
    final store = await AccountStore.open();
    await store.save(
      const AccountsState().withAccount(
        const Account(
          id: 'a',
          name: 'a',
          host: 'http://example.com',
          username: 'u',
          password: 'p',
          userAgent: defaultUserAgent,
        ),
      ),
    );
    final files = AccountFiles(Directory('${root.path}/accounts'));
    await files.sync({'a'});
    return (store, files);
  }))!;
  return ProviderContainer.test(
    overrides: [
      accountStoreProvider.overrideWithValue(store),
      accountFilesProvider.overrideWithValue(files),
      ...overrides,
    ],
  );
}
