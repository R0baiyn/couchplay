import 'dart:io';

import 'package:couchplay/catalog/category_filter.dart';
import 'package:couchplay/server/models.dart';
import 'package:flutter_test/flutter_test.dart';

List<Category> _fixture(String name) =>
    parseCategories(File('test/fixtures/$name.json').readAsStringSync());

Category _c(String name, [String id = '1']) => Category(id: id, name: name);

void main() {
  group('categoryTag', () {
    test('lit les préfixes courants', () {
      expect(categoryTag('FR · Drame'), 'FR');
      expect(categoryTag('FR | Drame'), 'FR');
      expect(categoryTag('|FR| Drame'), 'FR');
      expect(categoryTag('EN - Films'), 'EN');
      expect(categoryTag('VOST · Films'), 'VOST');
    });

    test('pas de préfixe : ni mot en minuscules, ni mot trop long', () {
      expect(categoryTag('Films 4K'), isNull);
      expect(categoryTag('UNKNOW - A Definir'), isNull);
      expect(categoryTag('TOP SPORTS'), isNull);
      expect(categoryTag('Séries NETFLIX'), isNull);
    });

    test('séries sans préfixe : la langue se lit dans le nom', () {
      expect(categoryTag('Séries SUB-AR'), 'AR');
      expect(categoryTag('Séries ARABES '), 'AR');
      expect(categoryTag('Séries ALGERIENNES'), 'AR');
      expect(categoryTag('Séries CARTOON ARABY'), 'AR');
      expect(categoryTag('Séries TURQUES'), 'TR');
    });
  });

  group('isAdultCategory', () {
    test('repère les mots-clés adultes', () {
      for (final name in ['XXX', 'Films Adult', 'FR · +18', 'Vidéos 18+']) {
        expect(isAdultCategory(name), isTrue, reason: name);
      }
    });

    test('garde visible la catégorie d\'animés au L remplacé', () {
      expect(isAdultCategory('Séries ANIMÉES POUR ADUƖTES'), isFalse);
      expect(isAdultCategory('FR · Drame'), isFalse);
    });
  });

  group('CatalogFilter', () {
    test('par défaut sur les films : FR et catégories sans pays', () {
      final visible = const CatalogFilter()
          .apply(ContentKind.movies, _fixture('vod_categories'))
          .map((c) => c.name)
          .toList();
      expect(visible, contains('FR · Drame'));
      expect(visible, contains('Films 4K'));
      expect(visible, isNot(contains('VOST · Films')));
      expect(visible, isNot(contains('EN · Films VO')));
      expect(visible.where((n) => n.startsWith('AR ·')), isEmpty);
      expect(visible.where((n) => n.startsWith('ES ·')), isEmpty);
    });

    test('par défaut sur les séries : tout sauf les étrangères', () {
      final visible = const CatalogFilter()
          .apply(ContentKind.series, _fixture('series_categories'))
          .map((c) => c.name)
          .toList();
      expect(visible, contains('Séries NETFLIX'));
      expect(visible, contains('Séries ANIMÉES POUR ADUƖTES'));
      expect(visible, isNot(contains('Séries SUB-AR')));
      expect(visible, isNot(contains('Séries TURQUES')));
    });

    test('liste de pays vide : tout afficher, sauf l\'adulte', () {
      const filter = CatalogFilter(tags: {});
      expect(filter.isVisible(ContentKind.movies, _c('AR · Films')), isTrue);
      expect(filter.isVisible(ContentKind.movies, _c('XXX')), isFalse);
      expect(
        const CatalogFilter(
          tags: {},
          showAdult: true,
        ).isVisible(ContentKind.movies, _c('XXX')),
        isTrue,
      );
    });

    test('un choix par catégorie l\'emporte sur le reste', () {
      final filter = CatalogFilter(
        overrides: {
          CatalogFilter.overrideKey(ContentKind.movies, '1'): true,
          CatalogFilter.overrideKey(ContentKind.movies, '2'): false,
        },
      );
      expect(
        filter.isVisible(ContentKind.movies, _c('AR · Films', '1')),
        isTrue,
      );
      expect(
        filter.isVisible(ContentKind.movies, _c('FR · Drame', '2')),
        isFalse,
      );
      // Même id côté séries : indépendant.
      expect(
        filter.isVisible(ContentKind.series, _c('AR · Films', '1')),
        isFalse,
      );
    });
  });

  test('detectTags liste les pays des catégories, triés, sans doublon', () {
    expect(detectTags(_fixture('vod_categories')), [
      'AR',
      'DZ',
      'EN',
      'ES',
      'FR',
      'IT',
      'TR',
      'VOST',
    ]);
  });
}
