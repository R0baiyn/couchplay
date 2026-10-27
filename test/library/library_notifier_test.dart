import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/library/library_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Account _account(String id) => Account(
  id: id,
  name: id,
  host: 'http://example.com',
  username: 'u',
  password: 'p',
  userAgent: defaultUserAgent,
);

void main() {
  late Directory root;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('couchplay_favorites_');
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<ProviderContainer> container() async {
    final store = await AccountStore.open();
    if (store.current.accounts.isEmpty) {
      await store.save(
        const AccountsState()
            .withAccount(_account('a'))
            .withAccount(_account('b')),
      );
    }
    final files = AccountFiles(Directory('${root.path}/accounts'));
    await files.sync({'a', 'b'});
    final container = ProviderContainer.test(
      overrides: [
        accountStoreProvider.overrideWithValue(store),
        accountFilesProvider.overrideWithValue(files),
      ],
    );
    container.listen(libraryProvider, (_, _) {});
    return container;
  }

  test('ajouter puis retirer un favori, conservé au redémarrage', () async {
    final first = await container();
    await first
        .read(libraryProvider.notifier)
        .toggleFavorite(key: 'movie:1', name: 'Inception');
    expect(first.read(libraryProvider).favorites.keys, ['movie:1']);
    first.dispose();

    final second = await container();
    expect(second.read(libraryProvider).favorites.keys, ['movie:1']);
    await second
        .read(libraryProvider.notifier)
        .toggleFavorite(key: 'movie:1', name: 'Inception');
    expect(second.read(libraryProvider).favorites, isEmpty);
  });

  test('deux comptes ont des favoris indépendants', () async {
    final c = await container();
    await c
        .read(libraryProvider.notifier)
        .toggleFavorite(key: 'series:45', name: 'Vikings');

    await c.read(accountsProvider.notifier).activate('b');
    expect(c.read(libraryProvider).favorites, isEmpty);

    await c.read(accountsProvider.notifier).activate('a');
    expect(c.read(libraryProvider).favorites.keys, ['series:45']);
  });
}
