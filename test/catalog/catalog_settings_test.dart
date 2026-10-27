import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/catalog/catalog_settings.dart';
import 'package:couchplay/catalog/category_filter.dart';
import 'package:couchplay/server/models.dart';
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
    root = Directory.systemTemp.createTempSync('couchplay_settings_');
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
    final container = ProviderContainer.test(
      overrides: [
        accountStoreProvider.overrideWithValue(store),
        accountFilesProvider.overrideWithValue(
          AccountFiles(Directory('${root.path}/accounts')),
        ),
      ],
    );
    container.listen(catalogFilterProvider, (_, _) {});
    return container;
  }

  test('par défaut : France, adulte masqué, aucun choix forcé', () async {
    final filter = (await container()).read(catalogFilterProvider);
    expect(filter.tags, {'FR'});
    expect(filter.showAdult, isFalse);
    expect(filter.overrides, isEmpty);
  });

  test('les choix survivent à un redémarrage', () async {
    final first = await container();
    final notifier = first.read(catalogFilterProvider.notifier);
    await notifier.setTag('AR', shown: true);
    await notifier.setShowAdult(true);
    first.dispose();

    final filter = (await container()).read(catalogFilterProvider);
    expect(filter.tags, {'FR', 'AR'});
    expect(filter.showAdult, isTrue);
  });

  test('deux comptes gardent des réglages indépendants', () async {
    final c = await container();
    await c.read(catalogFilterProvider.notifier).setShowAdult(true);

    await c.read(accountsProvider.notifier).activate('b');
    expect(c.read(catalogFilterProvider).showAdult, isFalse);

    await c.read(accountsProvider.notifier).activate('a');
    expect(c.read(catalogFilterProvider).showAdult, isTrue);
  });

  test(
    'forcer une catégorie, puis revenir à la règle efface le choix',
    () async {
      final c = await container();
      final notifier = c.read(catalogFilterProvider.notifier);
      const arabic = Category(id: '614', name: 'AR · Films');

      await notifier.setCategory(ContentKind.movies, arabic, shown: true);
      expect(c.read(catalogFilterProvider).overrides, {
        CatalogFilter.overrideKey(ContentKind.movies, '614'): true,
      });
      expect(
        c.read(catalogFilterProvider).isVisible(ContentKind.movies, arabic),
        isTrue,
      );

      await notifier.setCategory(ContentKind.movies, arabic, shown: false);
      expect(c.read(catalogFilterProvider).overrides, isEmpty);
    },
  );

  test(
    'un fichier de réglages illisible redonne les valeurs par défaut',
    () async {
      final dir = Directory('${root.path}/accounts/a')
        ..createSync(recursive: true);
      File('${dir.path}/catalog_settings.json')
          .writeAsStringSync('{pas du json');
      expect((await container()).read(catalogFilterProvider).tags, {'FR'});
    },
  );
}
