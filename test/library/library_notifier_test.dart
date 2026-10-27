import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/library/library.dart';
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

  PlayItem episode(String id, String series) => PlayItem.episode(
    id: id,
    extension: 'mkv',
    name: series,
    seriesId: series,
    season: 1,
    episode: 1,
  );

  test('fini sans durée connue : vu grâce à la durée enregistrée', () async {
    final c = await container();
    final library = c.read(libraryProvider.notifier);
    final item = episode('a', '45');
    await library.saveProgress(
      item,
      position: const Duration(seconds: 600),
      duration: const Duration(seconds: 3000),
    );
    await library.saveProgress(
      item,
      position: const Duration(seconds: 2850),
      duration: Duration.zero,
    );
    final saved = c.read(libraryProvider).progress[item.key]!;
    expect(saved.duration, const Duration(seconds: 3000));
    expect(saved.watched, isTrue);
  });

  test('« Retirer » un épisode retire toute sa série, rien d\'autre', () async {
    final c = await container();
    final library = c.read(libraryProvider.notifier);
    const movie = PlayItem.movie(id: '1', extension: 'mkv', name: 'Film');
    for (final item in [
      episode('a', '45'),
      episode('b', '45'),
      episode('x', '9'),
      movie,
    ]) {
      await library.saveProgress(
        item,
        position: const Duration(seconds: 600),
        duration: const Duration(seconds: 3000),
      );
    }
    await library.hide(c.read(libraryProvider).progress['episode:b']!);

    final progress = c.read(libraryProvider).progress;
    expect(progress['episode:a']!.hidden, isTrue);
    expect(progress['episode:b']!.hidden, isTrue);
    expect(progress['episode:a']!.position, const Duration(seconds: 600));
    expect(
      c.read(libraryProvider).continueWatching.map((p) => p.item.key).toSet(),
      {'episode:x', 'movie:1'},
    );
  });
}
