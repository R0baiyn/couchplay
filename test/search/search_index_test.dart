import 'dart:io';

import 'package:couchplay/catalog/catalog_cache.dart';
import 'package:couchplay/catalog/catalog_repository.dart';
import 'package:couchplay/catalog/category_filter.dart';
import 'package:couchplay/catalog/versions.dart';
import 'package:couchplay/search/search_index.dart';
import 'package:couchplay/server/item_name.dart';
import 'package:couchplay/server/models.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

// Comme au décodage des listes : le nom est décomposé une fois.
CatalogEntry entry(String name, {String id = '1'}) => CatalogEntry([
  CatalogItem(
    kind: ContentKind.movies,
    id: id,
    name: name,
    parsedName: ItemName.parse(name),
  ),
]);

List<String> titles(List<CatalogEntry> entries) => [
  for (final e in entries) e.item.name,
];

void main() {
  group('search', () {
    final entries = [
      entry('Le Fabuleux Destin d\'Amélie Poulain (2001)'),
      entry('FR - Inception 4K'),
      entry('Breaking Bad'),
      entry('Bad Boys (1995)'),
      entry('Le Prince d\'Égypte (1998)'),
    ];

    test('sans accents ni majuscules', () {
      expect(titles(search(entries, 'amelie')), [
        'Le Fabuleux Destin d\'Amélie Poulain (2001)',
      ]);
      expect(titles(search(entries, 'ÉGYPTE')), ['Le Prince d\'Égypte (1998)']);
    });

    test('préfixe pays et étiquettes ignorés', () {
      expect(titles(search(entries, 'inception')), ['FR - Inception 4K']);
      expect(search(entries, '4k'), isEmpty);
    });

    test('chaque mot doit apparaître, dans n\'importe quel ordre', () {
      expect(titles(search(entries, 'poulain destin')), hasLength(1));
      expect(search(entries, 'poulain egypte'), isEmpty);
    });

    test('début de titre d\'abord, puis l\'ordre de la liste', () {
      expect(titles(search(entries, 'bad')), [
        'Bad Boys (1995)',
        'Breaking Bad',
      ]);
    });

    test('n\'importe quelle version d\'un film', () {
      final grouped = CatalogEntry([
        const CatalogItem(
          kind: ContentKind.movies,
          id: '1',
          name: 'Acts of Vengeance SD',
        ),
        const CatalogItem(
          kind: ContentKind.movies,
          id: '2',
          name: 'Actes de Vengeance (2017) MULTI',
        ),
      ]);
      expect(search([grouped], 'actes'), hasLength(1));
      expect(search([grouped], 'acts'), hasLength(1));
    });

    test('recherche vide : tout', () {
      expect(search(entries, '  '), same(entries));
    });

    test('un index complet répond en moins de 100 ms', () {
      final big = [
        for (var i = 0; i < 30000; i++)
          entry('Film numéro $i (${1950 + i % 70}) FHD MULTI', id: '$i'),
      ];
      final watch = Stopwatch()..start();
      search(big, 'numero 2999');
      search(big, 'zzz');
      expect(watch.elapsedMilliseconds, lessThan(100));
    });
  });

  group('index complet', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('couchplay_index_'));
    tearDown(() => dir.deleteSync(recursive: true));

    CatalogRepository repository(FakeAdapter server) => CatalogRepository(
      ServerClient(
        host: 'http://example.com',
        username: 'u',
        password: 'p',
        userAgent: 'test',
        adapter: server,
      ),
      CatalogCache(dir, serverKey: 'k'),
    );

    test(
      'catégories visibles seules, versions regroupées, mis en cache',
      () async {
        final server = FakeAdapter.replying(
          File('test/fixtures/vod_streams.json').readAsStringSync(),
        );
        final categories = parseCategories(
          File('test/fixtures/vod_categories.json').readAsStringSync(),
        );
        // Filtre par défaut : français et adulte masqué.
        final visible = {
          for (final c in const CatalogFilter().apply(
            ContentKind.movies,
            categories,
          ))
            c.id,
        };
        final loaded = await repository(server)
            .all(ContentKind.movies, indexParser(ContentKind.movies, visible));

        expect(
          server.last!.uri.queryParameters,
          isNot(contains('category_id')),
        );
        final index = loaded.value;
        final libre = index.entryOf('144014')!;
        expect(libre.versions.map((v) => v.id), ['144016', '144015', '144014']);
        expect(index.entryOf('144016'), same(libre));
        // Film d'une catégorie arabe : masqué par défaut.
        expect(index.entryOf('19181'), isNull);

        // Grilles : chaque catégorie, avec ses seules versions.
        List<String>? names(String category) => [
          for (final entry in index.entriesIn(category) ?? <CatalogEntry>[])
            for (final version in entry.versions) version.name,
        ];
        expect(names('148'), [
          'Libre (2024) HD VF',
          'The King Tide (2024) HD VF',
        ]);
        expect(names('619'), ['Libre (2024) 4K']);
        // Visible mais vide ; masquée : inconnue de l'index.
        expect(index.entriesIn('118'), isEmpty);
        expect(index.entriesIn('614'), isNull);
        expect(File('${dir.path}/movies_all.json').existsSync(), isTrue);

        final again = await repository(server)
            .all(ContentKind.movies, indexParser(ContentKind.movies, visible));
        expect(again.savedAt, isNotNull);
        expect(server.calls, 1);
      },
    );
  });
}
