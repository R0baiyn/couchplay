import 'dart:convert';
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

import '../json_generators.dart';

const _account = Account(
  id: 'a',
  name: 'a',
  host: 'http://example.com',
  username: 'u',
  password: 'p',
  userAgent: defaultUserAgent,
);

String _encode(CatalogFilter f) => jsonEncode({
  'tags': f.tags.toList()..sort(),
  'showAdult': f.showAdult,
  'overrides': f.overrides,
});

void main() {
  late Directory root;
  late File file;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('couchplay_catalog_json_');
    file = File('${root.path}/accounts/a/catalog_settings.json');
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// Un conteneur neuf : relit le fichier, comme au lancement suivant.
  Future<ProviderContainer> container() async {
    final store = await AccountStore.open();
    await store.save(const AccountsState().withAccount(_account));
    final files = AccountFiles(Directory('${root.path}/accounts'));
    await files.sync({'a'});
    final container = ProviderContainer.test(
      overrides: [
        accountStoreProvider.overrideWithValue(store),
        accountFilesProvider.overrideWithValue(files),
      ],
    );
    container.listen(catalogFilterProvider, (_, _) {});
    return container;
  }

  group('aller-retour', () {
    test('80 suites de choix écrites, relues par un conteneur neuf', () async {
      final gen = Gen(70);
      var c = await container();
      for (var i = 0; i < 80; i++) {
        final notifier = c.read(catalogFilterProvider.notifier);
        switch (gen.between(0, 3)) {
          case 0:
            await notifier.setTag(
              gen.pick(['FR', 'AR', 'EN', 'VOST', gen.text()]),
              shown: gen.chance(),
            );
          case 1:
            await notifier.setShowAdult(gen.chance());
          case 2:
            await notifier.setCategory(
              gen.pick(ContentKind.values),
              Category(
                id: gen.pick(['1', '614', '0', gen.safeId()]),
                name: gen.pick(['FR · Drame', 'AR · Films', 'XXX', gen.text()]),
              ),
              shown: gen.chance(),
            );
          default:
            if (gen.chance(0.3)) await notifier.resetCategories();
        }
        final written = c.read(catalogFilterProvider);
        c.dispose();
        c = await container();
        expect(
          _encode(c.read(catalogFilterProvider)),
          _encode(written),
          reason: 'itération $i',
        );
      }
      c.dispose();
    });
  });

  group('fichier abîmé', () {
    Future<CatalogFilter> read(String content) async {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
      final c = await container();
      addTearDown(c.dispose);
      return c.read(catalogFilterProvider);
    }

    test(
      'vide, tronqué, pas du JSON : filtre par défaut, fichier laissé',
      () async {
        final text = _encode(
          const CatalogFilter(
            tags: {'AR', 'EN'},
            showAdult: true,
            overrides: {'movies:1': true},
          ),
        );
        final gen = Gen(71);
        final bad = [
          '',
          '  ',
          '{pas du json',
          for (var i = 0; i < 30; i++)
            text.substring(0, gen.between(1, text.length - 1)),
        ];
        for (final content in bad) {
          expect(_encode(await read(content)), _encode(const CatalogFilter()));
          expect(file.readAsStringSync(), content);
        }
      },
    );

    test(
      'JSON valide mais pas un objet : filtre sans tags (rien de forcé)',
      () async {
        // Un objet vide ne dit pas « France » : tags vide = tous les pays.
        for (final content in ['[]', '"texte"', '42', 'null', '{}']) {
          final filter = await read(content);
          expect(filter.tags, isEmpty, reason: content);
          expect(filter.showAdult, isFalse);
          expect(filter.overrides, isEmpty);
        }
      },
    );

    test('valeurs mal typées : entrées ignorées une à une', () async {
      final filter = await read(
        jsonEncode({
          'tags': ['FR', 5, null, '', '  ', [], 'AR'],
          'showAdult': 'on',
          'overrides': {
            'movies:1': true,
            'movies:2': 'off',
            'series:3': 'peut-être',
            'series:4': [],
            'movies:5': null,
          },
        }),
      );
      expect(filter.tags, {'FR', '5', 'AR'});
      expect(filter.showAdult, isTrue);
      expect(filter.overrides, {'movies:1': true, 'movies:2': false});
    });

    test('champ inconnu en plus : ignoré, perdu à la réécriture', () async {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'tags': ['AR'],
            'futur': 1,
          }),
        );
      final c = await container();
      addTearDown(c.dispose);
      expect(c.read(catalogFilterProvider).tags, {'AR'});
      await c.read(catalogFilterProvider.notifier).setShowAdult(true);
      expect(file.readAsStringSync(), isNot(contains('futur')));
    });

    test('valeurs mutées au hasard : jamais d\'exception', () async {
      final gen = Gen(72);
      const base = CatalogFilter(
        tags: {'AR', 'EN'},
        showAdult: true,
        overrides: {'movies:1': true, 'series:2': false},
      );
      for (var i = 0; i < 80; i++) {
        final mutated = gen.mutate(jsonDecode(_encode(base)), rate: 0.2);
        final String text;
        try {
          text = jsonEncode(mutated);
        } on JsonUnsupportedObjectError {
          continue;
        }
        await read(text);
      }
    });
  });
}
