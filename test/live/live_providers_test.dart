import 'dart:convert';
import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/accounts/server_session.dart';
import 'package:couchplay/live/channel.dart';
import 'package:couchplay/live/live_providers.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

Account _account(String id) => Account(
  id: id,
  name: id,
  host: 'http://$id.example.com',
  username: 'u',
  password: 'p',
  userAgent: defaultUserAgent,
);

void main() {
  late Directory root;
  late Map<String, FakeAdapter> servers;

  final fixtures = {
    'get_live_categories': File('test/fixtures/live_categories.json')
        .readAsStringSync(),
    'get_live_streams': File('test/fixtures/live_streams.json')
        .readAsStringSync(),
  };
  // Compte b : une seule chaîne, dans une catégorie de même id que chez a.
  final other = {
    'get_live_categories': jsonEncode([
      {'category_id': '104', 'category_name': 'FRANCE B'},
    ]),
    'get_live_streams': jsonEncode([
      {'stream_id': 7777, 'name': 'Chaîne B', 'category_id': '104'},
    ]),
  };

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('couchplay_live_providers_');
    servers = {
      'a': FakeAdapter.routes(fixtures),
      'b': FakeAdapter.routes(other),
    };
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<ProviderContainer> container() async {
    final store = await AccountStore.open();
    await store.save(
      const AccountsState()
          .withAccount(_account('a'))
          .withAccount(_account('b')),
    );
    final files = AccountFiles(Directory('${root.path}/accounts'));
    await files.sync({'a', 'b'});
    final container = ProviderContainer.test(
      overrides: [
        accountStoreProvider.overrideWithValue(store),
        accountFilesProvider.overrideWithValue(files),
        serverClientFactoryProvider.overrideWithValue(
          (account) => ServerClient(
            host: account.host,
            username: account.username,
            password: account.password,
            userAgent: account.userAgent,
            adapter: servers[account.id],
          ),
        ),
      ],
    );
    container.listen(visibleChannelsProvider, (_, _) {});
    container.listen(visibleLiveCategoriesProvider, (_, _) {});
    return container;
  }

  Future<void> activate(ProviderContainer container, String id) async {
    await container.read(accountsProvider.notifier).activate(id);
    await container.read(liveCatalogProvider.future);
  }

  List<String> ids(AsyncValue<List<Channel>> value) => [
    for (final channel in value.requireValue) channel.id,
  ];

  test(
    'catégories visibles, chaînes d’une catégorie, toutes les visibles',
    () async {
      final c = await container();
      await activate(c, 'a');

      expect(
        [
          for (final category
              in c.read(visibleLiveCategoriesProvider).requireValue)
            category.id,
        ],
        ['104', '1', '105', '543', '12', '1739', '1826', '1811'],
      );
      expect(ids(c.read(liveChannelsProvider('104'))), [
        '9001',
        '9002',
        '9003',
        '9004',
        '9005',
      ]);
      expect(c.read(liveChannelsProvider('inconnue')).requireValue, isEmpty);
      // Dans l'ordre des catégories visibles : ni Belgique, ni Radio.
      expect(ids(c.read(visibleChannelsProvider)), [
        for (var i = 9001; i <= 9015; i++) '$i',
      ]);
    },
  );

  test('changement de compte : aucune chaîne de l’un chez l’autre', () async {
    final c = await container();
    await activate(c, 'a');
    expect(ids(c.read(visibleChannelsProvider)), hasLength(15));

    await activate(c, 'b');
    expect(ids(c.read(visibleChannelsProvider)), ['7777']);
    expect(ids(c.read(liveChannelsProvider('104'))), ['7777']);
    // Chaque compte a son cache, dans son dossier.
    for (final (id, expected) in [('a', '9001'), ('b', '7777')]) {
      final cached = File('${root.path}/accounts/$id/live/live_streams.json')
          .readAsStringSync();
      expect(cached, contains(expected), reason: id);
    }

    await activate(c, 'a');
    expect(ids(c.read(visibleChannelsProvider)), isNot(contains('7777')));
  });

  test('« Actualiser » interroge le serveur malgré le cache', () async {
    final c = await container();
    await activate(c, 'a');
    expect(servers['a']!.calls, 2);
    await c.read(liveCatalogProvider.notifier).refresh();
    expect(servers['a']!.calls, 4);
    expect(c.read(liveCatalogProvider).requireValue.offline, isFalse);
  });
}
