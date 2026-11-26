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
        .addFavorite(key: 'movie:1', name: 'Mirage');
    expect(first.read(libraryProvider).favorites.keys, ['movie:1']);
    first.dispose();

    final second = await container();
    expect(second.read(libraryProvider).favorites.keys, ['movie:1']);
    await second.read(libraryProvider.notifier).removeFavorites(['movie:1']);
    expect(second.read(libraryProvider).favorites, isEmpty);
    second.dispose();

    final third = await container();
    expect(third.read(libraryProvider).favorites, isEmpty);
  });

  test('deux comptes ont des favoris indépendants', () async {
    final c = await container();
    await c
        .read(libraryProvider.notifier)
        .addFavorite(key: 'series:45', name: 'Les Veilleurs');

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

  test(
    'marquer un épisode vu ou non vu ne fait pas revenir sa série',
    () async {
      final c = await container();
      final library = c.read(libraryProvider.notifier);
      final old = episode('a', '45');
      await library.saveProgress(
        old,
        position: const Duration(seconds: 600),
        duration: const Duration(seconds: 3000),
      );
      await library.saveProgress(
        episode('b', '45'),
        position: const Duration(seconds: 600),
        duration: const Duration(seconds: 3000),
      );
      final before = c.read(libraryProvider).progress['episode:a']!.updatedAt;
      await library.hide(c.read(libraryProvider).progress['episode:b']!);

      await library.setWatched(old, watched: true);
      await library.setWatched(episode('c', '45'), watched: true);
      await library.setWatched(old, watched: false);

      final progress = c.read(libraryProvider).progress;
      expect(progress['episode:a']!.updatedAt, before);
      expect(progress['episode:a']!.hidden, isTrue);
      expect(progress['episode:c']!.hidden, isTrue);
      expect(c.read(libraryProvider).continueWatching, isEmpty);
    },
  );

  test('retirer une ligne et effacer, conservés au redémarrage', () async {
    final first = await container();
    final library = first.read(libraryProvider.notifier);
    await library.addFavorite(key: 'movie:1', name: 'Mirage');
    for (final item in [episode('a', '45'), episode('b', '9')]) {
      await library.saveProgress(
        item,
        position: const Duration(seconds: 600),
        duration: const Duration(seconds: 3000),
      );
    }
    await library.removeProgress('episode:a');
    first.dispose();

    final second = await container();
    expect(second.read(libraryProvider).progress.keys, ['episode:b']);
    await second.read(libraryProvider.notifier).clearHistory();
    second.dispose();

    final third = await container();
    expect(third.read(libraryProvider).progress, isEmpty);
    expect(third.read(libraryProvider).favorites.keys, ['movie:1']);
  });

  test('chaînes favorites et récentes : par compte, gardées au redémarrage, '
      "récentes effacées avec l'historique", () async {
    final first = await container();
    final library = first.read(libraryProvider.notifier);
    await library.addChannelFavorite(id: '7', name: 'Sept', number: 7);
    await library.addRecentChannel(id: '8', name: 'Huit');
    await library.addRecentChannel(id: '9', name: 'Neuf', logo: 'https://x/9');
    expect(first.read(libraryProvider).isChannelFavorite('7'), isTrue);

    await first.read(accountsProvider.notifier).activate('b');
    expect(first.read(libraryProvider).channelFavorites, isEmpty);
    expect(first.read(libraryProvider).recentChannels, isEmpty);
    await first
        .read(libraryProvider.notifier)
        .addRecentChannel(id: '1', name: 'Une de B');
    await first.read(accountsProvider.notifier).activate('a');
    expect(first.read(libraryProvider).recentChannels.map((c) => c.id), [
      '9',
      '8',
    ]);
    first.dispose();

    final second = await container();
    final state = second.read(libraryProvider);
    expect(state.channelFavorites.single.number, 7);
    expect(state.recentChannels.first.logo, 'https://x/9');
    await second.read(libraryProvider.notifier).removeChannelFavorite('7');
    await second
        .read(libraryProvider.notifier)
        .addChannelFavorite(id: '2', name: 'Deux');
    await second.read(libraryProvider.notifier).clearHistory();
    second.dispose();

    final third = await container();
    expect(third.read(libraryProvider).recentChannels, isEmpty);
    expect(third.read(libraryProvider).channelFavorites.map((c) => c.id), [
      '2',
    ]);
    await third.read(accountsProvider.notifier).activate('b');
    expect(third.read(libraryProvider).recentChannels.map((c) => c.id), ['1']);
  });
}
