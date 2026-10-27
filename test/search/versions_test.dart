import 'package:couchplay/catalog/versions.dart';
import 'package:couchplay/library/library.dart';
import 'package:couchplay/server/models.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogItem movie(String id, String name, {String? tmdb}) =>
    CatalogItem(kind: ContentKind.movies, id: id, name: name, tmdbId: tmdb);

List<List<String>> names(List<CatalogEntry> entries) => [
  for (final entry in entries) [for (final v in entry.versions) v.name],
];

void main() {
  group('entriesOf', () {
    test('même tmdb_id : une affiche, la meilleure version d\'abord', () {
      final entries = entriesOf([
        movie('1', 'Libre (2024) HD VF', tmdb: '9'),
        movie('2', 'Autre'),
        movie('3', 'Libre (2024) 4K', tmdb: '9'),
        movie('4', 'Libre (2024) FHD VF', tmdb: '9'),
      ]);
      expect(names(entries), [
        ['Libre (2024) 4K', 'Libre (2024) FHD VF', 'Libre (2024) HD VF'],
        ['Autre'],
      ]);
      expect(entries.first.title, 'Libre (2024)');
    });

    test('sans tmdb_id : même titre et même année', () {
      final entries = entriesOf([
        movie('1', 'Alien, le huitième passager (1979) SD'),
        movie('2', 'ALIEN, le huitième passager (1979) FHD MULTI'),
      ]);
      expect(entries, hasLength(1));
      expect(entries.single.item.id, '2');
    });

    test('homonymes d\'années différentes : jamais fusionnés', () {
      final entries = entriesOf([
        movie('1', 'Dune (1984) HD'),
        movie('2', 'Dune (2021) 4K'),
        movie('3', 'Dune SD'),
      ]);
      expect(entries, hasLength(3));
    });

    test('titres différents d\'un même tmdb_id : regroupés', () {
      final entries = entriesOf([
        movie('1', 'Acts of Vengeance SD', tmdb: '44'),
        movie('2', 'Actes de Vengeance (2017) MULTI', tmdb: '44'),
      ]);
      expect(entries, hasLength(1));
    });

    test('séries jamais regroupées', () {
      CatalogItem series(String id) =>
          CatalogItem(kind: ContentKind.series, id: id, name: 'Dark');
      expect(entriesOf([series('1'), series('2')]), hasLength(2));
    });

    test('version originale après l\'audio français, même en 4K', () {
      final entries = entriesOf([
        movie('1', 'Film (2020) 4K VOSTFR', tmdb: '1'),
        movie('2', 'Film (2020) HD VF', tmdb: '1'),
      ]);
      expect(entries.single.item.id, '2');
    });

    test('affiche : la première version qui en a une', () {
      final entry = CatalogEntry([
        movie('1', 'A'),
        const CatalogItem(
          kind: ContentKind.movies,
          id: '2',
          name: 'A',
          poster: 'https://img/a.jpg',
        ),
      ]);
      expect(entry.poster, 'https://img/a.jpg');
    });
  });

  test('étiquettes : nom, sinon place ; doublons numérotés', () {
    expect(
      versionLabels([
        movie('1', 'Venom (4K MULTI)'),
        movie('2', 'Venom (2018)'),
        movie('3', 'Venom HD VF'),
        movie('4', 'Venom HD VF'),
        movie('5', 'Venom SD'),
      ]),
      ['4K MULTI', 'Version 2', 'HD VF', 'HD VF (2)', 'SD'],
    );
  });

  group('preferredVersion', () {
    final versions = [
      movie('1', 'A 4K'),
      movie('2', 'A HD'),
      movie('3', 'A SD'),
    ];
    final at = DateTime.utc(2026, 10, 27);

    Progress progress(String id, DateTime updatedAt) => Progress(
      item: PlayItem.movie(id: id, extension: 'mkv', name: 'A'),
      position: const Duration(minutes: 5),
      duration: const Duration(hours: 2),
      updatedAt: updatedAt,
    );

    test('rien : la meilleure', () {
      expect(preferredVersion(versions, const Library()).id, '1');
    });

    test('favori : celui-là', () {
      final library = const Library().withFavorite(
        Favorite(key: 'movie:3', name: 'A SD', addedAt: at),
      );
      expect(preferredVersion(versions, library).id, '3');
    });

    test('regardée : la plus récente, avant le favori', () {
      final library = const Library()
          .withFavorite(Favorite(key: 'movie:3', name: 'A SD', addedAt: at))
          .withProgress(progress('1', at))
          .withProgress(progress('2', at.add(const Duration(days: 1))));
      expect(preferredVersion(versions, library).id, '2');
    });
  });
}
