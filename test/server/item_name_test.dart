import 'package:couchplay/server/item_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalize', () {
    test('minuscules, accents français retirés', () {
      expect(
        normalize('Le Fabuleux Destin d\'Amélie Poulain'),
        'le fabuleux destin d amelie poulain',
      );
      expect(
        normalize('ÉTÉ çà œuvre Æon ÎÏÔÖÙÛÜ'),
        'ete ca oeuvre aeon iioouuu',
      );
    });

    test('ponctuation et espaces typographiques : un seul espace', () {
      expect(normalize('Alien : Covenant'), 'alien covenant');
      expect(normalize('L’Été — « fou » !'), 'l ete fou');
      expect(normalize('  À   la  '), 'a la');
    });

    test('autres alphabets gardés', () {
      expect(normalize('بلا حدود'), 'بلا حدود');
    });
  });

  group('ItemName.parse', () {
    test('étiquettes de qualité et de langue, année à part', () {
      final name = ItemName.parse('Libre (2024) HD VF');
      expect(name.display, 'Libre (2024)');
      expect(name.text, 'libre');
      expect(name.year, 2024);
      expect(name.quality, 'HD');
      expect(name.language, 'VF');
      expect(name.label, 'HD VF');
    });

    test('préfixe pays retiré', () {
      final name = ItemName.parse('FR - Inception 4K');
      expect(name.text, 'inception');
      expect(name.display, 'Inception');
      expect(name.label, '4K');
      expect(ItemName.parse('FR · Drame').text, 'drame');
      expect(ItemName.parse('|FR| Titre').text, 'titre');
    });

    test('pas de préfixe inventé : codes inconnus ou sans séparateur', () {
      expect(ItemName.parse('ABBA - Gold').text, 'abba gold');
      expect(ItemName.parse('IT (2017)').text, 'it');
    });

    test('étiquettes entre parenthèses : parenthèses vides retirées', () {
      final name = ItemName.parse('Venom (4K MULTI)');
      expect(name.display, 'Venom');
      expect(name.label, '4K MULTI');
      expect(ItemName.parse('21 grammes (HD VF)').display, '21 grammes');
    });

    test('mots entiers en majuscules : HD ne vient pas de FHD', () {
      final name = ItemName.parse('Alien (FHD MULTI)');
      expect(name.quality, 'FHD');
      expect(ItemName.parse('Le hd des sd').label, isNull);
    });

    test('année seulement entre parenthèses', () {
      final name = ItemName.parse('Blade Runner 2049 (2017) FHD VOST');
      expect(name.text, 'blade runner 2049');
      expect(name.year, 2017);
      expect(name.frenchAudio, isFalse);
      expect(ItemName.parse('Blade Runner 2049').year, isNull);
    });

    test('rang : 4K, FHD, HD, sans étiquette, SD', () {
      int rank(String name) => ItemName.parse(name).qualityRank;
      expect(rank('A 4K'), greaterThan(rank('A FHD')));
      expect(rank('A FHD'), greaterThan(rank('A HD')));
      expect(rank('A HD'), greaterThan(rank('A')));
      expect(rank('A'), greaterThan(rank('A SD')));
    });

    test(
      'nom fait seulement d\'étiquettes : gardé tel quel à l\'affichage',
      () {
        final name = ItemName.parse(' 4K ');
        expect(name.display, '4K');
        expect(name.text, '');
      },
    );
  });
}
