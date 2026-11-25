import 'dart:convert';
import 'dart:io';

import 'package:couchplay/library/library.dart';
import 'package:couchplay/library/library_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../json_generators.dart';

String _encode(Library library) => jsonEncode(library.toJson());

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('couchplay_library_json_');
    file = File('${dir.path}${Platform.pathSeparator}library.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('aller-retour', () {
    test(
      '200 bibliothèques générées : relues, puis réencodées à l\'identique',
      () {
        final gen = Gen(38);
        for (var i = 0; i < 200; i++) {
          final library = gen.library();
          final first = _encode(library);
          final back = Library.fromJson(jsonDecode(first));
          expect(_encode(back), first, reason: 'itération $i');
          expect(back.favorites.length, library.favorites.length);
          expect(back.progress.length, library.progress.length);
          expect(back.channelFavorites.length, library.channelFavorites.length);
          expect(back.recentChannels.length, library.recentChannels.length);
        }
      },
    );

    test('50 bibliothèques par l\'écriture atomique réelle', () async {
      final gen = Gen(39);
      for (var i = 0; i < 50; i++) {
        final library = gen.library();
        await LibraryStore(file).save(library);
        expect(
          _encode(LibraryStore(file).load()),
          _encode(library),
          reason: 'itération $i',
        );
      }
      expect(File('${file.path}.bak').existsSync(), isFalse);
    });
  });

  group('fichier abîmé', () {
    Library load() => LibraryStore(file).load();

    test('vide ou blanc : bibliothèque vide, rien mis de côté', () {
      for (final content in ['', '   \n\t']) {
        file.writeAsStringSync(content);
        expect(load().favorites, isEmpty);
        expect(file.existsSync(), isTrue);
        expect(File('${file.path}.bak').existsSync(), isFalse);
      }
    });

    test('tronqué en 100 endroits : vide, original gardé en .bak', () {
      final library = Gen(40).library().withFavorite(Gen(40).favorite());
      final text = const JsonEncoder.withIndent(' ').convert(library.toJson());
      final gen = Gen(41);
      final bak = File('${file.path}.bak');
      for (var i = 0; i < 100; i++) {
        // Moins que le texte entier : l'accolade finale manque toujours.
        final part = text.substring(0, gen.between(1, text.length - 3));
        file.writeAsStringSync(part);
        if (bak.existsSync()) bak.deleteSync();
        final loaded = load();
        if (part.trim().isEmpty) {
          expect(loaded.favorites, isEmpty);
          continue;
        }
        expect(loaded.favorites, isEmpty, reason: 'coupé à ${part.length}');
        expect(loaded.progress, isEmpty);
        expect(file.existsSync(), isFalse, reason: 'mis de côté');
        expect(bak.readAsStringSync(), part);
      }
    });

    test(
      'JSON valide mais pas un objet : bibliothèque vide, fichier laissé',
      () {
        for (final content in ['[]', '"texte"', '42', 'null', 'true']) {
          file.writeAsStringSync(content);
          expect(load().favorites, isEmpty, reason: content);
          expect(file.readAsStringSync(), content);
          expect(File('${file.path}.bak').existsSync(), isFalse);
        }
      },
    );

    test('rubriques mal typées : vides ; entrées mal typées : ignorées', () {
      expect(
        Library.fromJson({'favorites': [], 'progress': 'x'}).favorites,
        isEmpty,
      );
      final library = Library.fromJson({
        'favorites': {
          'movie:1': 5,
          'movie:2': {'name': []},
          'movie:3': {'name': '  '},
          'film:4': {'name': 'Clé inconnue'},
          'series:': {'name': 'Sans id'},
          // Un nombre devient du texte : l'entrée est gardée.
          'movie:5': {'name': 7, 'poster': 3, 'addedAt': 'pas une date'},
          'series:6': {'name': 'Série', 'addedAt': 1700000000},
        },
        'progress': {
          'movie:1': {'name': 'Film', 'extension': 'mkv'},
          'movie:2': {'name': 'Film', 'extension': 'mkv', 'position': '90'},
          'movie:3': {'name': 'Film'},
          'episode:4': {'name': 'S', 'extension': 'mkv', 'seriesId': 9},
          'episode:5': {
            'name': 'S',
            'extension': 'mkv',
            'seriesId': 9,
            'season': '2',
            'episode': 3.0,
          },
          'foo:6': {'name': 'Film', 'extension': 'mkv'},
        },
      });
      expect(library.favorites.keys, ['movie:5', 'series:6']);
      expect(library.favorites['movie:5']!.name, '7');
      expect(library.favorites['movie:5']!.poster, '3');
      expect(library.favorites['movie:5']!.addedAt.millisecondsSinceEpoch, 0);
      expect(library.progress.keys, ['movie:1', 'movie:2', 'episode:5']);
      // Valeurs absentes : par défaut (0, ni vu ni retiré).
      final p1 = library.progress['movie:1']!;
      expect(
        (p1.position, p1.duration, p1.watched, p1.hidden),
        (Duration.zero, Duration.zero, false, false),
      );
      expect(
        library.progress['movie:2']!.position,
        const Duration(seconds: 90),
      );
      expect(library.progress['episode:5']!.item.season, 2);
    });

    test(
      'champ inconnu en plus : ignoré, puis perdu à la réécriture',
      () async {
        file.writeAsStringSync(
          jsonEncode({
            'version': 1,
            'futur': {'a': 1},
            'favorites': {
              'movie:1': {'name': 'A', 'nouveau': true},
            },
          }),
        );
        final library = load();
        expect(library.favorites.keys, ['movie:1']);
        await LibraryStore(file).save(library);
        expect(file.readAsStringSync(), isNot(contains('futur')));
        expect(file.readAsStringSync(), isNot(contains('nouveau')));
      },
    );

    test('valeurs mutées au hasard : jamais d\'exception', () {
      final gen = Gen(42);
      for (var i = 0; i < 300; i++) {
        final json = jsonDecode(_encode(gen.library()));
        final mutated = gen.mutate(json);
        // Chaque entrée est relue seule : la bibliothèque ne lève jamais.
        final library = Library.fromJson(mutated);
        _encode(library);
        library.continueWatching;
        library.history;
      }
    });

    test('fichier muté au hasard : le magasin rend une bibliothèque', () {
      final gen = Gen(43);
      for (var i = 0; i < 60; i++) {
        final mutated = gen.mutate(jsonDecode(_encode(gen.library())));
        // NaN et infini ne s'écrivent pas en JSON : ils sont écartés avant.
        final String text;
        try {
          text = jsonEncode(mutated);
        } on JsonUnsupportedObjectError {
          continue;
        }
        file.writeAsStringSync(text);
        expect(load, returnsNormally);
      }
    });
  });

  test("titre d'épisode enregistré avec le préfixe du fournisseur : relu "
      'sans lui (D-061)', () {
    final item = PlayItem.fromJson('episode:7', {
      'seriesId': '4',
      'season': 1,
      'episode': 2,
      'title': 'Les Navigateurs - S01E02 - Le Retour',
      'name': 'Les Navigateurs',
      'extension': 'mkv',
    });
    expect(item?.episodeTitle, 'Le Retour');
  });
}
