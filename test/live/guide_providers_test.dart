import 'dart:convert';
import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/accounts/server_session.dart';
import 'package:couchplay/catalog/catalog_cache.dart';
import 'package:couchplay/catalog/catalog_repository.dart';
import 'package:couchplay/catalog/catalog_settings.dart';
import 'package:couchplay/live/channel.dart';
import 'package:couchplay/live/guide.dart';
import 'package:couchplay/live/guide_repository.dart';
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

/// Dépôt sans réseau ni fichier : répond [_answer] tout de suite.
final class _FakeRepository extends GuideRepository {
  _FakeRepository(this._answer)
    : super(
        ServerClient(
          host: 'http://f.example.com',
          username: 'u',
          password: 'p',
          userAgent: 't',
        ),
        CatalogCache(Directory('inutilise'), serverKey: 'k'),
      );

  final Loaded<Guide> Function(Set<String> channels, bool refresh) _answer;

  @override
  Future<Loaded<Guide>> guide(
    Set<String> channels, {
    bool refresh = false,
  }) async => _answer(channels, refresh);
}

void main() {
  late Directory root;
  late String? xml;
  late int downloads;
  late int downloadsB;
  late bool catalogBDown;
  late bool guideBDown;

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
    catalogBDown = false;
    guideBDown = false;
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
        return catalogBDown
            ? ResponseBody.fromString('', 500)
            : routesB.fetch(options, null, null);
      }
      downloadsB++;
      if (guideBDown) return ResponseBody.fromString('', 500);
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
    // Comme l'écran : le filtre et les chaînes visibles restent écoutés.
    c.listen(visibleChannelsProvider, (_, _) {});
    await c.read(accountsProvider.notifier).activate('a');
    await c.read(liveCatalogProvider.future);
    return c;
  }

  /// Guide une fois les chaînes chargées (le premier, vide, les attend).
  Future<Guide> guide(ProviderContainer c) async {
    c.read(visibleChannelsProvider);
    return (await c.read(guideProvider.future)).value;
  }

  test(
    'toutes les chaînes du catalogue sont cherchées, visibles ou non',
    () async {
      final c = await container();
      final loaded = await guide(c);
      // BELGIUM (chaine8) et UK (channel9) sont masquées, mais cherchées : le
      // filtre ne relit jamais le guide. Pas la radio, ni les chaînes sans id.
      expect(loaded.channels, {
        'chaine1.test',
        'chaine2.test',
        'absente.test',
        'sansprogramme.test',
        '12345',
        'chaine7.test',
        'sport1.test',
        'sport3.test',
        'chaine8.test',
        'channel9.test',
      });
      expect(
        loaded.programmes.keys,
        unorderedEquals(['chaine1.test', 'chaine7.test', 'chaine8.test']),
      );
      expect(
        c.read(onAirProvider('chaine1.test'))?.current?.title,
        'Sur chaine1.test',
      );
      expect(c.read(onAirProvider('chaine2.test')), isNull);
    },
  );

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

  test(
    'filtre : cocher ou décocher une catégorie ne retélécharge rien',
    () async {
      final c = await container();
      await guide(c);
      expect(downloads, 1);
      const belgium = Category(id: '60', name: 'BELGIUM');
      final filter = c.read(catalogFilterProvider.notifier);

      await filter.setLiveCategory(belgium, shown: true);
      final more = await guide(c);
      expect(more.programmes.keys, contains('chaine8.test'));
      expect(
        c.read(onAirProvider('chaine8.test'))?.current?.title,
        'Sur chaine8.test',
      );

      await filter.setLiveCategory(belgium, shown: false);
      await guide(c);
      expect(downloads, 1);
    },
  );

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

  test('compte B dont le catalogue échoue, sans cache : aucun guide de B '
      'demandé avec les chaînes de A', () async {
    final c = await container();
    expect((await guide(c)).programmes, isNotEmpty);
    catalogBDown = true;

    await c.read(accountsProvider.notifier).activate('b');
    await expectLater(c.read(liveCatalogProvider.future), throwsA(anything));
    final loaded = (await c.read(guideProvider.future)).value;
    expect(downloadsB, 0);
    // Rien de A sous B.
    expect(loaded.programmes, isEmpty);
    expect(
      File('${root.path}/accounts/b/live/guide.json').existsSync(),
      isFalse,
    );
  });

  test('compte B dont le guide échoue : rien du guide de A sous B', () async {
    final c = await container();
    expect((await guide(c)).programmes, isNotEmpty);
    guideBDown = true;

    await c.read(accountsProvider.notifier).activate('b');
    await c.read(liveCatalogProvider.future);
    final loaded = await guide(c);
    expect(downloadsB, 1);
    expect(loaded.programmes, isEmpty);
  });

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

  group('rechargement quotidien', () {
    final start = DateTime.utc(2026, 11, 24, 12);
    final fixed = Guide(
      channels: const {'a.fr'},
      programmes: {
        'a.fr': [programmeAt(start, -600, 600, 'A')],
      },
    );

    /// Conteneur sous horloge factice, dépôt qui répond [answer] sans réseau
    /// ni fichier ; rend le nombre de chargements.
    (ProviderContainer, List<DateTime>) fake(
      FakeAsync async,
      Loaded<Guide> Function(DateTime now) answer,
    ) {
      final calls = <DateTime>[];
      DateTime now() => start.add(async.elapsed);
      final c = ProviderContainer.test(
        overrides: [
          guideNowProvider.overrideWithValue(now),
          liveCatalogProvider.overrideWithBuild(
            (ref, notifier) async => Loaded(
              LiveCatalog(const [], const [
                Channel(id: '1', name: 'A', epgChannelId: 'a.fr'),
              ]),
            ),
          ),
          guideRepositoryProvider.overrideWithValue(
            _FakeRepository((ids, refresh) {
              calls.add(now());
              return answer(now());
            }),
          ),
        ],
      );
      c.listen(guideProvider, (_, _) {});
      async.elapse(Duration.zero);
      return (c, calls);
    }

    test('guide téléchargé : relu 24 h plus tard, pas avant', () {
      fakeAsync((async) {
        final (c, calls) = fake(async, (_) => Loaded(fixed));
        expect(calls, hasLength(1));
        async.elapse(const Duration(hours: 23, minutes: 59));
        expect(calls, hasLength(1));
        async.elapse(const Duration(minutes: 1));
        expect(calls, hasLength(2));
        c.dispose();
      });
    });

    test('cache de 20 h : relu 4 h plus tard', () {
      fakeAsync((async) {
        final (c, calls) = fake(
          async,
          (now) =>
              Loaded(fixed, savedAt: now.subtract(const Duration(hours: 20))),
        );
        async.elapse(const Duration(hours: 3, minutes: 59));
        expect(calls, hasLength(1));
        async.elapse(const Duration(minutes: 1));
        expect(calls, hasLength(2));
        c.dispose();
      });
    });

    test(
      'échec au rechargement des 24 h : le guide reste, réessai dans 1 h',
      () {
        fakeAsync((async) {
          var fail = false;
          final (c, calls) = fake(async, (_) {
            if (fail) throw const InvalidResponse('HTTP 500');
            return Loaded(fixed);
          });
          fail = true;
          async.elapse(const Duration(hours: 24));
          expect(calls, hasLength(2));
          expect(c.read(guideProvider).value?.value.programmes, isNotEmpty);
          async.elapse(const Duration(minutes: 59));
          expect(calls, hasLength(2));
          async.elapse(const Duration(minutes: 1));
          expect(calls, hasLength(3));
          expect(c.read(guideProvider).value?.value.programmes, isNotEmpty);
          c.dispose();
        });
      },
    );

    test('1er chargement raté : un essai par heure, pas plus', () {
      fakeAsync((async) {
        final (c, calls) = fake(async, (_) => throw const ServerUnreachable());
        expect(calls, hasLength(1));
        expect(c.read(guideProvider).value?.value.programmes, isEmpty);
        async.elapse(const Duration(minutes: 59));
        expect(calls, hasLength(1));
        async.elapse(const Duration(hours: 3, minutes: 1));
        expect(calls, hasLength(5));
        c.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test(
      'hors ligne avec un vieux cache : un essai par heure, pas de boucle',
      () {
        fakeAsync((async) {
          final (c, calls) = fake(
            async,
            (now) => Loaded(
              fixed,
              offline: true,
              savedAt: now.subtract(const Duration(days: 3)),
            ),
          );
          expect(calls, hasLength(1));
          async.elapse(const Duration(minutes: 59));
          expect(calls, hasLength(1));
          async.elapse(const Duration(minutes: 1));
          expect(calls, hasLength(2));
          async.elapse(const Duration(hours: 3));
          expect(calls, hasLength(5));
          c.dispose();
          expect(async.pendingTimers, isEmpty);
        });
      },
    );
  });
}
