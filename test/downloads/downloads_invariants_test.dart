import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/downloads/download.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/library/library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../json_generators.dart';
import 'video_server.dart';

/// Les contenus que les suites d'actions ajoutent, retirent, mettent en
/// pause : peu d'identifiants, pour que les actions se croisent.
final _pool = [
  for (var i = 1; i <= 4; i++)
    PlayItem.movie(id: '$i', extension: 'mkv', name: 'Film $i'),
  for (var i = 1; i <= 2; i++)
    PlayItem.episode(
      id: 'e$i',
      extension: 'mp4',
      name: 'Série',
      seriesId: '9',
      season: 1,
      episode: i,
    ),
];

Account _account(String id) => Account(
  id: id,
  name: id,
  host: 'http://example.com',
  username: 'moi',
  password: 'p$id',
  userAgent: defaultUserAgent,
);

final _source = Uint8List.fromList(List.generate(1000, (i) => i % 251));

/// Les états de la file ; « en cours » compte comme « en attente » : la file
/// peut démarrer l'entrée entre deux lectures, sans rapport avec la reprise.
Map<String, DownloadStatus> _statuses(ProviderContainer c) => {
  for (final MapEntry(:key, :value)
      in c.read(downloadsProvider).entries.entries)
    key: value.status == DownloadStatus.running
        ? DownloadStatus.queued
        : value.status,
};

/// Ce qui doit être vrai de la file à tout instant.
void _checkInvariants(ProviderContainer c, String where) {
  final entries = c.read(downloadsProvider).entries;
  final notifier = c.read(downloadsProvider.notifier);
  final running = entries.values.where(
    (d) => d.status == DownloadStatus.running,
  );
  expect(
    running.length,
    lessThanOrEqualTo(1),
    reason: '$where : deux en cours',
  );
  for (final MapEntry(:key, :value) in entries.entries) {
    expect(value.key, key, reason: '$where : clé $key');
    expect(value.received, greaterThanOrEqualTo(0), reason: '$where : $key');
    if (value.size > 0) {
      expect(
        value.received,
        lessThanOrEqualTo(value.size),
        reason: '$where : $key a plus d\'octets que sa taille',
      );
    }
    if (value.status == DownloadStatus.ready) {
      expect(
        notifier.fileOf(value.item)?.existsSync(),
        isTrue,
        reason: '$where : $key prête sans fichier',
      );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Une suite d'actions générées, puis le retour au calme.
  Future<void> run(int seed) async {
    final gen = Gen(seed);
    final root = Directory.systemTemp.createTempSync('couchplay_invariants_');
    FlutterSecureStorage.setMockInitialValues({});
    final accounts = await AccountStore.open();
    await accounts.save(
      const AccountsState()
          .withAccount(_account('a'))
          .withAccount(_account('b')),
    );
    final files = AccountFiles(Directory('${root.path}/accounts'));
    await files.sync({'a', 'b'});
    final server = VideoServer(_source, hangAtCut: true);
    final c = ProviderContainer.test(
      overrides: [
        accountStoreProvider.overrideWithValue(accounts),
        accountFilesProvider.overrideWithValue(files),
        downloadFilesProvider.overrideWithValue(
          AccountFiles(Directory('${root.path}/downloads')),
        ),
        downloadAdapterProvider.overrideWithValue(server),
        downloadRetryDelaysProvider.overrideWithValue(const [Duration.zero]),
        freeSpaceProvider.overrideWithValue((_) async => null),
        pauseInBackgroundProvider.overrideWithValue(false),
        mobileOnlyNetworkProvider.overrideWith((ref) => Stream.value(false)),
      ],
    );
    c.listen(downloadsProvider, (_, _) {});
    DownloadsNotifier notifier() => c.read(downloadsProvider.notifier);
    String key() => gen.pick(_pool).key;

    try {
      for (var step = 0; step < 14; step++) {
        final where = 'graine $seed, pas $step';
        switch (gen.between(0, 9)) {
          case 0 || 1:
            await notifier().add([
              for (var i = 0; i < gen.between(1, 3); i++) gen.pick(_pool),
            ]);
          case 2:
            await notifier().pause(key());
          case 3:
            await notifier().resume(key());
          case 4:
            await notifier().remove(key());
          case 5:
            // Le serveur coupe la connexion et la laisse pendue.
            server
              ..status = null
              ..cutAt = 300;
          case 6:
            // Le serveur refuse : les transferts échouent.
            server
              ..cutAt = null
              ..status = 404;
          case 7:
            server
              ..cutAt = null
              ..status = null;
          case 8:
            await c
                .read(accountsProvider.notifier)
                .activate(gen.pick(['a', 'b']));
          default:
            // Une reprise demandée deux fois donne le même état.
            final k = key();
            await notifier().resume(k);
            final once = _statuses(c);
            await notifier().resume(k);
            expect(_statuses(c), once, reason: '$where : reprise doublée');
        }
        await Future<void>.delayed(Duration(milliseconds: gen.between(0, 12)));
        _checkInvariants(c, where);
      }

      // Retour au calme : le serveur répond, tout ce qui est arrêté repart.
      server
        ..cutAt = null
        ..status = null;
      for (final account in ['a', 'b']) {
        await c.read(accountsProvider.notifier).activate(account);
        for (final item in _pool) {
          // Un flux pendu est coupé par la pause, puis repris par Range.
          await notifier().pause(item.key);
          await notifier().resume(item.key);
        }
        for (var i = 0; i < 500; i++) {
          final busy = _statuses(c).values.any(
            (s) => s == DownloadStatus.queued || s == DownloadStatus.running,
          );
          if (!busy) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        _checkInvariants(c, 'graine $seed, calme $account');
        for (final entry in c.read(downloadsProvider).entries.values) {
          expect(
            entry.status,
            DownloadStatus.ready,
            reason: '$seed ${entry.key}',
          );
          expect(
            notifier().fileOf(entry.item)!.readAsBytesSync(),
            _source,
            reason: '$seed ${entry.key} : octets',
          );
        }
        // Le manifeste écrit dit la même chose que l'état.
        await SerialFileWriter.flushAll();
        final manifest = DownloadsStore(
          File(files.path(account, 'downloads.json')),
          Directory('${root.path}/downloads/$account'),
        ).load();
        expect(
          manifest.keys.toSet(),
          c.read(downloadsProvider).entries.keys.toSet(),
          reason: '$seed $account : manifeste',
        );
      }
    } finally {
      c.dispose();
      await SerialFileWriter.flushAll();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // Sans effet sur les tests suivants.
      }
    }
  }

  test('12 suites de 14 actions générées : les invariants tiennent', () async {
    for (var seed = 100; seed < 112; seed++) {
      await run(seed);
    }
  });
}
