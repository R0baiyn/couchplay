import 'dart:io';

import 'package:couchplay/downloads/export.dart';
import 'package:couchplay/library/library.dart';
import 'package:flutter_test/flutter_test.dart';

PlayItem movie(String name, {String extension = 'mkv'}) =>
    PlayItem.movie(id: '12', extension: extension, name: name);

void main() {
  group('exportFileName', () {
    test('film : le titre et l\'extension de la vidéo', () {
      expect(exportFileName(movie('Mirage')), 'Mirage.mkv');
      expect(
        exportFileName(movie('Éloïse à côté', extension: 'mp4')),
        'Éloïse à côté.mp4',
      );
    });

    test('épisode : série, S01E02 sur deux chiffres, titre', () {
      const item = PlayItem.episode(
        id: '34',
        extension: 'mp4',
        name: 'Les Voisins',
        seriesId: '5',
        season: 1,
        episode: 2,
        episodeTitle: 'La clé',
      );
      expect(exportFileName(item), 'Les Voisins S01E02 La clé.mp4');
      const sans = PlayItem.episode(
        id: '34',
        extension: 'mp4',
        name: 'Les Voisins',
        seriesId: '5',
        season: 12,
        episode: 103,
      );
      expect(exportFileName(sans), 'Les Voisins S12E103.mp4');
    });

    test('caractères interdits remplacés, rien de dangereux', () {
      final name = exportFileName(movie('..\\..\\a/b: "c" <d>|e?*\u0007\n'));
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains('\\')));
      expect(name, isNot(contains('..')));
      expect(name, isNot(matches(RegExp(r'[<>:"|?*\x00-\x1f]'))));
      expect(name, endsWith('.mkv'));
      expect(name, startsWith('_'));
    });

    test('un titre fait de points ou d\'espaces donne le nom de repli', () {
      expect(exportFileName(movie('..')), 'movie-12.mkv');
      expect(exportFileName(movie('  . ')), 'movie-12.mkv');
      expect(exportFileName(movie('')), 'movie-12.mkv');
    });

    test('points et espaces de fin retirés', () {
      expect(exportFileName(movie('Fin... ')), 'Fin.mkv');
    });

    test('noms réservés évités, quelle que soit la casse', () {
      for (final reserved in ['CON', 'nul', 'Com1', 'LPT9', 'aux.txt']) {
        expect(
          exportFileName(movie(reserved)),
          startsWith('_'),
          reason: reserved,
        );
      }
      expect(exportFileName(movie('Console')), 'Console.mkv');
    });

    test('longueur bornée, sans couper un caractère en deux', () {
      final name = exportFileName(movie('é' * 300));
      expect(name.length, 120 + '.mkv'.length);
      final emoji = exportFileName(movie('🎬' * 300));
      expect(emoji.runes.length, 120 + '.mkv'.length);
      expect(() => emoji.codeUnits, returnsNormally);
    });
  });

  group('exportVideo', () {
    late Directory root;
    late File source;
    late Directory target;

    setUp(() {
      root = Directory.systemTemp.createTempSync('export_test');
      source = File('${root.path}/movie-12.mkv')
        ..writeAsBytesSync(List.generate(5000, (i) => i % 251));
      target = Directory('${root.path}/choisi')..createSync();
    });
    tearDown(() => root.deleteSync(recursive: true));

    List<String> names() => [
      for (final e in target.listSync())
        e.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
    ]..sort();

    test('copie sous le nom d\'export, la source reste', () async {
      final file = await exportVideo(source, target, 'Mirage.mkv');
      expect(file.path, '${target.path}${Platform.pathSeparator}Mirage.mkv');
      expect(file.readAsBytesSync(), source.readAsBytesSync());
      expect(source.existsSync(), isTrue);
      expect(names(), ['Mirage.mkv']);
    });

    test('un titre dangereux reste dans le dossier choisi', () async {
      final name = exportFileName(movie(r'..\..\evil/CON: x'));
      final file = await exportVideo(source, target, name);
      expect(file.parent.path, target.path);
      expect(names(), [name]);
      expect(
        root.listSync().map((e) => e.path),
        isNot(contains(endsWith('evil'))),
      );
    });

    test('un fichier .part de l\'utilisateur reste intact', () async {
      final mine = File('${target.path}/Mirage.mkv.part')
        ..writeAsStringSync('téléchargement du navigateur');
      await exportVideo(source, target, 'Mirage.mkv');
      expect(mine.readAsStringSync(), 'téléchargement du navigateur');
      expect(names(), ['Mirage.mkv', 'Mirage.mkv.part']);
    });

    test('deux exports en même temps : deux fichiers complets', () async {
      // Deux films de même titre, exportés pendant la même copie.
      final files = await Future.wait([
        exportVideo(source, target, 'Mirage.mkv'),
        exportVideo(source, target, 'Mirage.mkv'),
      ]);
      expect(names(), ['Mirage (2).mkv', 'Mirage.mkv']);
      for (final file in files) {
        expect(file.readAsBytesSync(), source.readAsBytesSync());
      }
    });

    test(
      'nom déjà pris : le premier est intact, le second a un suffixe',
      () async {
        File('${target.path}/Mirage.mkv').writeAsStringSync('mon fichier');
        final second = await exportVideo(source, target, 'Mirage.mkv');
        final third = await exportVideo(source, target, 'Mirage.mkv');
        expect(
          File('${target.path}/Mirage.mkv').readAsStringSync(),
          'mon fichier',
        );
        expect(second.uri.pathSegments.last, 'Mirage (2).mkv');
        expect(third.uri.pathSegments.last, 'Mirage (3).mkv');
        expect(second.readAsBytesSync(), source.readAsBytesSync());
        expect(names(), ['Mirage (2).mkv', 'Mirage (3).mkv', 'Mirage.mkv']);
      },
    );

    test('vidéo disparue : message clair, rien créé', () async {
      source.deleteSync();
      await expectLater(
        exportVideo(source, target, 'Mirage.mkv'),
        throwsA(
          isA<ExportException>().having(
            (e) => e.message,
            'message',
            'La vidéo n\'existe plus.',
          ),
        ),
      );
      expect(names(), isEmpty);
    });

    test('dossier choisi disparu : message clair', () async {
      target.deleteSync();
      await expectLater(
        exportVideo(source, target, 'Mirage.mkv'),
        throwsA(isA<ExportException>()),
      );
      expect(target.existsSync(), isFalse);
    });

    test('erreur après la copie : pas de fichier partiel', () async {
      // Un dossier à la place du nom final : la copie réussit, le nom ne
      // peut pas être pris.
      Directory('${target.path}/Mirage.mkv').createSync();
      await expectLater(
        exportVideo(source, target, 'Mirage.mkv'),
        throwsA(isA<ExportException>()),
      );
      expect(names(), ['Mirage.mkv']);
      expect(
        FileSystemEntity.isDirectorySync(target.listSync().single.path),
        isTrue,
      );
    });
  });
}
