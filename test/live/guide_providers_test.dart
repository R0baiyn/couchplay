import 'dart:convert';
import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/accounts/server_session.dart';
import 'package:couchplay/catalog/catalog_settings.dart';
import 'package:couchplay/live/guide.dart';
import 'package:couchplay/live/live_providers.dart';
import 'package:couchplay/server/models.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';
import '../support/fixed_guide.dart';

String _date(DateTime t) {
  final p = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${p.year}${two(p.month)}${two(p.day)}${two(p.hour)}${two(p.minute)}'
      '${two(p.second)} +0000';
}

/// Un programme en cours d'une heure sur chacune des chaînes [ids].
String _guide(List<String> ids, DateTime now) {
  final start = _date(now.subtract(const Duration(minutes: 30)));
  final stop = _date(now.add(const Duration(minutes: 30)));
  return '<tv>${[for (final id in ids) '<programme start="$start" stop="$stop" channel="$id">'
        '<title>Sur $id</title></programme>'].join()}</tv>';
}

void main() {
  late Directory root;
  late String? xml;
  late int downloads;
  late int downloadsB;

  final fixtures = {
    'get_live_categories': File('test/fixtures/live_categories.json')
        .readAsStringSync(),
    'get_live_streams': File('test/fixtures/live_streams.json')
        .readAsStringSync(),
  };

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('couchplay_guide_providers_');
    // chaine8.test : seulement dans BELGIUM, masquée par défaut.
    xml = _guide([
      'chaine1.test',
      'chaine7.test',
      'chaine8.test',
    ], DateTime.now());
    downloads = 0;
    downloadsB = 0;
  });
  tearDown(() => root.deleteSync(recursive: true));

  final routes = FakeAdapter.routes(fixtures);
  // Compte b : une chaîne, dans une catégorie de même id que chez a.
  final routesB = FakeAdapter.routes({
    'get_live_categories': jsonEncode([
      {'category_id': '104', 'category_name': 'FRANCE B'},
    ]),
    'get_live_streams': jsonEncode([
      {
        'stream_id': 7777,
        'name': 'Chaîne B',
        'category_id': '104',
        'epg_channel_id': 'b.test',
      },
    ]),
  });
  final server = FakeAdapter((options) async {
    if (options.uri.host == 'b.example.com') {
      if (options.uri.path != '/xmltv.php') {
        return routesB.fetch(options, null, null);
      }
      downloadsB++;
      final now = DateTime.now();
      return ResponseBody.fromString(
        _guide(['b.test', 'chaine1.test'], now),
        200,
      );
    }
    if (options.uri.path != '/xmltv.php') {
      return routes.fetch(options, null, null);
    }
    downloads++;
    final body = xml;
    return body == null
        ? ResponseBody.fromString('', 404)
        : ResponseBody.fromString(body, 200);
  });

  Future<ProviderContainer> container() async {
    final store = await AccountStore.open();
    var accounts = const AccountsState();
    for (final id in ['a', 'b']) {
      accounts = accounts.withAccount(
        Account(
          id: id,
          name: id,
          host: 'http://$id.example.com',
          username: 'u',
          password: 'p',
          userAgent: defaultUserAgent,
        ),
      );
    }
    await store.save(accounts);
    final files = AccountFiles(Directory('${root.path}/accounts'));
    await files.sync({'a', 'b'});
    final c = ProviderContainer.test(
      overrides: [
        accountStoreProvider.overrideWithValue(store),
        accountFilesProvider.overrideWithValue(files),
        serverClientFactoryProvider.overrideWithValue(
          (account) => ServerClient(
            host: account.host,
            username: account.username,
            password: account.password,
            userAgent: account.userAgent,
            adapter: server,
          ),
        ),
      ],
    );
    c.listen(guideProvider, (_, _) {});
    await c.read(accountsProvider.notifier).activate('a');
    await c.read(liveCatalogProvider.future);
    return c;
  }

  /// Guide une fois les chaînes chargées (le premier, vide, les attend).
  Future<Guide> guide(ProviderContainer c) async {
    c.read(visibleChannelsProvider);
    return (await c.read(guideProvider.future)).value;
  }

  test('seules les chaînes visibles sont cherchées dans le guide', () async {
    final c = await container();
    final loaded = await guide(c);
    // D-081 : sans le filtre des chaînes visibles, BELGIUM et UK y seraient.
    expect(loaded.channels, {
      'chaine1.test',
      'chaine2.test',
      'absente.test',
      'sansprogramme.test',
      '12345',
      'chaine7.test',
      'sport1.test',
      'sport3.test',
    });
    expect(
      loaded.programmes.keys,
      unorderedEquals(['chaine1.test', 'chaine7.test']),
    );
    expect(
      c.read(onAirProvider('chaine1.test'))?.current?.title,
      'Sur chaine1.test',
    );
    expect(c.read(onAirProvider('chaine8.test')), isNull);
    expect(c.read(onAirProvider('chaine2.test')), isNull);
  });

  test('pas de guide (serveur sans guide) : guide vide, sans erreur, les '
      'chaînes restent', () async {
    xml = null;
    final c = await container();
    final loaded = await guide(c);
    expect(loaded.programmes, isEmpty);
    expect(c.read(guideProvider).hasError, isFalse);
    expect(c.read(visibleChannelsProvider).requireValue, hasLength(15));
    expect(c.read(onAirProvider('chaine1.test')), isNull);
  });

  test('filtre : une chaîne de plus retélécharge, une de moins non', () async {
    final c = await container();
    await guide(c);
    expect(downloads, 1);
    const belgium = Category(id: '60', name: 'BELGIUM');
    final filter = c.read(catalogFilterProvider.notifier);

    await filter.setLiveCategory(belgium, shown: true);
    final more = await guide(c);
    expect(downloads, 2);
    expect(more.programmes.keys, contains('chaine8.test'));

    await filter.setLiveCategory(belgium, shown: false);
    await guide(c);
    expect(downloads, 2);
  });

  test(
    'par compte : chacun son guide, son cache, un seul téléchargement',
    () async {
      final c = await container();
      expect((await guide(c)).programmes.keys, contains('chaine1.test'));

      await c.read(accountsProvider.notifier).activate('b');
      await c.read(liveCatalogProvider.future);
      final b = await guide(c);
      expect(b.channels, {'b.test'});
      expect(b.programmes.keys, ['b.test']);
      // Jamais demandé à b avec les chaînes de a.
      expect(downloadsB, 1);
      final cached = File('${root.path}/accounts/b/live/guide.json')
          .readAsStringSync();
      expect(cached, isNot(contains('chaine1.test')));

      await c.read(accountsProvider.notifier).activate('a');
      await c.read(liveCatalogProvider.future);
      final a = await guide(c);
      expect(a.programmes.keys, isNot(contains('b.test')));
      // Le cache de a sert encore.
      expect(downloads, 1);
    },
  );

  test('« Actualiser » qui échoue : le guide affiché reste', () async {
    final c = await container();
    await guide(c);
    xml = null;
    await c.read(guideProvider.notifier).refresh();
    expect(downloads, 2);
    expect(
      c.read(guideProvider).requireValue.value.programmes.keys,
      contains('chaine1.test'),
    );
  });

  test('« Actualiser » retélécharge malgré le cache', () async {
    final c = await container();
    await guide(c);
    await c.read(guideProvider.notifier).refresh();
    expect(downloads, 2);
  });

  test('programmes d’une chaîne sur une plage', () async {
    final c = await container();
    await guide(c);
    final now = DateTime.now();
    final range = (
      channel: 'chaine1.test',
      from: now.subtract(const Duration(hours: 2)),
      to: now.add(const Duration(hours: 2)),
    );
    c.listen(guideRangeProvider(range), (_, _) {});
    expect(
      [for (final p in c.read(guideRangeProvider(range))) p.title],
      ['Sur chaine1.test'],
    );
  });

  group('minuterie', () {
    final start = DateTime.utc(2026, 11, 24, 12);
    Programme programme(int from, int to, String title) =>
        programmeAt(start, from, to, title);
    final fixed = Guide(
      channels: const {'a.fr', 'b.fr'},
      programmes: {
        // A finit dans 90 s, puis B.
        'a.fr': [programme(-600, 90, 'A'), programme(90, 3600, 'B')],
        // Commence dans 5 min.
        'b.fr': [programme(300, 900, 'Plus tard')],
      },
    );

    ProviderContainer fake(FakeAsync async, Guide guide) {
      final c = ProviderContainer.test(
        overrides: [
          guideProvider.overrideWith(() => FixedGuide(guide)),
          guideNowProvider.overrideWithValue(() => start.add(async.elapsed)),
        ],
      );
      c.listen(onAirProvider('a.fr'), (_, _) {});
      c.listen(onAirProvider('b.fr'), (_, _) {});
      // Riverpod reconstruit par une minuterie de durée nulle.
      async.elapse(Duration.zero);
      return c;
    }

    test('à la fin du programme en cours, le suivant ; chaque minute, '
        'l’avancement', () {
      fakeAsync((async) {
        final c = fake(async, fixed);
        OnAir? a() => c.read(onAirProvider('a.fr'));
        expect(a()?.current?.title, 'A');
        expect(a()?.next?.title, 'B');
        expect(a()!.progress, closeTo(600 / 690, 1e-9));

        async.elapse(const Duration(seconds: 60));
        expect(a()?.current?.title, 'A');
        expect(a()!.progress, closeTo(660 / 690, 1e-9));

        async.elapse(const Duration(seconds: 29));
        expect(a()?.current?.title, 'A');
        async.elapse(const Duration(seconds: 1));
        expect(a()?.current?.title, 'B');
        expect(a()?.next, isNull);

        // b.fr : rien en cours, puis le programme à son début.
        expect(c.read(onAirProvider('b.fr'))?.current, isNull);
        expect(c.read(onAirProvider('b.fr'))?.next?.title, 'Plus tard');
        async.elapse(const Duration(seconds: 210));
        expect(c.read(onAirProvider('b.fr'))?.current?.title, 'Plus tard');
        c.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('une seule minuterie, aucune sans guide', () {
      fakeAsync((async) {
        final c = fake(async, fixed);
        expect(async.pendingTimers, hasLength(1));
        c.dispose();
        expect(
          async.pendingTimers,
          isEmpty,
          reason: async.pendingTimersDebugString.join('\n'),
        );

        final empty = fake(async, Guide.empty);
        expect(empty.read(onAirProvider('a.fr')), isNull);
        expect(
          async.pendingTimers,
          isEmpty,
          reason: async.pendingTimersDebugString.join('\n'),
        );
        empty.dispose();
      });
    });
  });
}
