import 'dart:io';

import 'package:couchplay/catalog/catalog_cache.dart';
import 'package:couchplay/catalog/catalog_repository.dart';
import 'package:couchplay/catalog/category_filter.dart';
import 'package:couchplay/catalog/versions.dart';
import 'package:couchplay/catalog/catalog_index.dart';
import 'package:couchplay/live/channel.dart';
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
      entry('Le Fabuleux Destin d\'Éloïse Marchand (2001)'),
      entry('FR - Mirage 4K'),
      entry('Going Bad'),
      entry('Bad Boys (1995)'),
      entry('Le Secret d\'Égypte (1998)'),
    ];

    test('sans accents ni majuscules', () {
      expect(titles(search(entries, 'eloise')), [
        'Le Fabuleux Destin d\'Éloïse Marchand (2001)',
      ]);
      expect(titles(search(entries, 'ÉGYPTE')), ['Le Secret d\'Égypte (1998)']);
    });

    test('préfixe pays et étiquettes ignorés', () {
      expect(titles(search(entries, 'mirage')), ['FR - Mirage 4K']);
      expect(search(entries, '4k'), isEmpty);
    });

    test('chaque mot doit apparaître, dans n\'importe quel ordre', () {
      expect(titles(search(entries, 'marchand destin')), hasLength(1));
      expect(search(entries, 'marchand egypte'), isEmpty);
    });

    test('début de titre d\'abord, puis l\'ordre de la liste', () {
      expect(titles(search(entries, 'bad')), ['Bad Boys (1995)', 'Going Bad']);
    });

    test('n\'importe quelle version d\'un film', () {
      final grouped = CatalogEntry([
        const CatalogItem(
          kind: ContentKind.movies,
          id: '1',
          name: 'Acts of Clarity SD',
        ),
        const CatalogItem(
          kind: ContentKind.movies,
          id: '2',
          name: 'Actes de Clarté (2017) MULTI',
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
      // Le meilleur de trois essais : la machine chargée (tests en parallèle)
      // ne doit pas rendre le test rouge au hasard.
      var best = 1 << 30;
      for (var i = 0; i < 3; i++) {
        final watch = Stopwatch()..start();
        search(big, 'numero 2999');
        search(big, 'zzz');
        if (watch.elapsedMilliseconds < best) best = watch.elapsedMilliseconds;
      }
      expect(best, lessThan(100));
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
        final horizon = index.entryOf('144014')!;
        expect(horizon.versions.map((v) => v.id), [
          '144016',
          '144015',
          '144014',
        ]);
        expect(index.entryOf('144016'), same(horizon));
        // Film d'une catégorie arabe : masqué par défaut.
        expect(index.entryOf('19181'), isNull);

        // Grilles : chaque catégorie, avec ses seules versions.
        List<String>? names(String category) => [
          for (final entry in index.entriesIn(category) ?? <CatalogEntry>[])
            for (final version in entry.versions) version.name,
        ];
        expect(names('148'), [
          'Horizon (2024) HD VF',
          'Marée Haute (2024) HD VF',
        ]);
        expect(names('619'), ['Horizon (2024) 4K']);
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

  group('chaînes', () {
    List<SearchableChannel> index(List<String> names) => [
      for (final (i, name) in names.indexed)
        (channel: Channel(id: '$i', name: name), text: normalize(name)),
    ];
    List<String> found(List<String> names, String query) => [
      for (final c in searchChannels(index(names), query)) c.name,
    ];

    test('même normalisation que les films : accents, casse, mots dans le '
        'désordre', () {
      final names = ["L'ÉQUIPE FHD", 'Équipe 21', 'Arte HD', 'TV5 Monde'];
      // « Équipe 21 » commence par la recherche : devant.
      expect(found(names, 'equipe'), ['Équipe 21', "L'ÉQUIPE FHD"]);
      expect(found(names, 'hd arte'), ['Arte HD']);
      expect(found(names, 'monde tv5'), ['TV5 Monde']);
      expect(found(names, 'zzz'), isEmpty);
    });

    test('qualités d\'une même chaîne : deux résultats, pas fusionnés', () {
      expect(found(["L'EQUIPE FHD", "L'EQUIPE SD"], "l'equipe"), [
        "L'EQUIPE FHD",
        "L'EQUIPE SD",
      ]);
    });

    test('nom qui commence par la recherche : devant, ordre gardé sinon', () {
      expect(found(['Sport Arena', 'Euro Sport 2', 'Sport 1'], 'sport'), [
        'Sport Arena',
        'Sport 1',
        'Euro Sport 2',
      ]);
    });
  });

  group('sections des résultats', () {
    List<SearchFilter>? sections(
      SearchFilter filter, {
      bool movies = true,
      bool series = true,
      bool channels = true,
      bool channelsPending = false,
    }) => searchSections(
      filter,
      movies: movies,
      series: series,
      channels: channels,
      channelsPending: channelsPending,
    );
    const m = SearchFilter.movies;
    const s = SearchFilter.series;
    const tv = SearchFilter.live;

    test('les puces et leurs noms', () {
      expect(SearchFilter.values.map((f) => f.name), [
        'all',
        'movies',
        'series',
        'live',
      ]);
    });

    test('« Tout » : Films, Séries puis TV, sans les types vides', () {
      expect(sections(SearchFilter.all), [m, s, tv]);
      expect(sections(SearchFilter.all, series: false), [m, tv]);
      expect(sections(SearchFilter.all, movies: false, series: false), [tv]);
    });

    test('une puce ne garde que son type, vide s\'il n\'a rien', () {
      expect(sections(m), [m]);
      expect(sections(s), [s]);
      expect(sections(tv), [tv]);
      expect(sections(s, series: false), isEmpty);
    });

    test('chaînes en chargement : on attend pour TV, et pour « Tout » sans '
        'rien d\'autre', () {
      List<SearchFilter>? pending(SearchFilter filter, {bool others = true}) =>
          sections(
            filter,
            movies: others,
            series: others,
            channels: false,
            channelsPending: true,
          );
      expect(pending(tv), isNull);
      expect(pending(SearchFilter.all, others: false), isNull);
      expect(pending(SearchFilter.all), [m, s]);
      expect(pending(m), [m]);
      // Films déjà connus : « rien de ce type » sans attendre les chaînes.
      expect(pending(m, others: false), isEmpty);
    });
  });
}
