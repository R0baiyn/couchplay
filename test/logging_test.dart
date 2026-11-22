import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:couchplay/logging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Valeurs fictives, assemblées par interpolation dans les URL.
  const host = 'http://srv.example.net:8080';
  const user = 'jean.d';
  const pass = 'p4ss-w0rd';

  group('redact', () {
    test(
      'masque user et mot de passe dans la query string, dans les deux ordres',
      () {
        expect(
          redact('$host/player_api.php?username=$user&password=$pass&action=x'),
          '$host/player_api.php?username=***&password=***&action=x',
        );
        expect(
          redact('$host/player_api.php?action=x&password=$pass&username=$user'),
          '$host/player_api.php?action=x&password=***&username=***',
        );
      },
    );

    test('masque des valeurs encodées en URL', () {
      final encoded = Uri.encodeQueryComponent('a&b #"c');
      expect(
        redact('$host/player_api.php?username=$user&password=$encoded'),
        '$host/player_api.php?username=***&password=***',
      );
    });

    test('masque les chemins de flux movie, series, live et timeshift', () {
      for (final kind in ['movie', 'series', 'live', 'timeshift']) {
        expect(
          redact('$host/$kind/$user/$pass/42.mkv'),
          '$host/$kind/***/***/42.mkv',
          reason: kind,
        );
      }
      expect(
        redact('$host/timeshift/$user/$pass/60/2026-10-26:20-00/42.ts'),
        '$host/timeshift/***/***/60/2026-10-26:20-00/42.ts',
      );
    });

    test(
      "masque un chemin de flux dont l'identifiant porte une apostrophe",
      () {
        // `Uri.encodeComponent` laisse `'` dans un segment de chemin.
        expect(
          redact("$host/movie/u'x/p'y/42.mkv"),
          '$host/movie/***/***/42.mkv',
        );
        expect(redact("$host/u'x/p'y/42.ts"), '$host/***/***/42.ts');
        expect(
          redact("lien '$host/movie/$user/$pass/42.mkv' refusé"),
          "lien '$host/movie/***/***/42.mkv' refusé",
        );
      },
    );

    test('masque la forme courte hôte/user/mot de passe/id du direct', () {
      expect(redact('$host/$user/$pass/42'), '$host/***/***/42');
      expect(redact('$host/$user/$pass/42.ts'), '$host/***/***/42.ts');
    });

    test('masque les identifiants placés avant l\'hôte', () {
      expect(
        redact('http://$user:$pass@srv.example.net/x'),
        'http://***:***@srv.example.net/x',
      );
    });

    test('masque une URL au milieu d\'un message d\'erreur', () {
      final message = redact(
        'DioException [connection timeout]: '
        '$host/player_api.php?username=$user&password=$pass failed',
      );
      expect(message, isNot(contains(user)));
      expect(message, isNot(contains(pass)));
      expect(message, startsWith('DioException [connection timeout]: '));
      expect(message, endsWith(' failed'));
    });

    test('masque en plus les secrets connus, même hors d\'une URL', () {
      final message = redact(
        'mot de passe refusé : $pass (${Uri.encodeComponent(pass)})',
        secrets: [user, pass],
      );
      expect(message, 'mot de passe refusé : *** (***)');
    });

    test('masque le nom de session dans un chemin de fichier', () {
      expect(
        redact(r'FileSystemException: C:\Users\jean\AppData\x.json'),
        r'FileSystemException: C:\Users\***\AppData\x.json',
      );
      expect(
        redact('Cannot open /home/jean/.local/x'),
        'Cannot open /home/***/.local/x',
      );
    });

    test('masque les identifiants sous forme JSON, même tronqués', () {
      expect(
        redact('{"user_info":{"username":"$user","password" : "$pass"}}'),
        '{"user_info":{"username":"***","password" : "***"}}',
      );
      expect(
        redact('{"username":"a\\"b","password":1234,"x":1}'),
        '{"username":"***","password":"***","x":1}',
      );
      expect(
        redact('{"Username":null,"PASSWORD":true}'),
        '{"Username":"***","PASSWORD":"***"}',
      );
      // Aperçu coupé à 120 caractères au milieu de la valeur.
      expect(redact('{"password":"$pass'), '{"password":"***"');
    });

    test(
      'ignore les secrets vides et laisse un texte sans identifiant intact',
      () {
        const text =
            'Catalogue chargé : 1234 films, https://image.example.org/a.jpg';
        expect(redact(text, secrets: ['', ' ']), text);
      },
    );
  });

  group('journal', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('couchplay_journal_');
      file = File('${dir.path}${Platform.pathSeparator}couchplay.log');
    });
    tearDown(() async {
      await closeJournal();
      dir.deleteSync(recursive: true);
    });

    test('rien n\'est écrit dans un fichier sans ouverture', () async {
      expect(journalFile, isNull);
      log('GET $host/player_api.php?username=$user&password=$pass');
      await flushJournal();
      expect(dir.listSync(), isEmpty);
      expect(await readJournalTail(), isEmpty);
    });

    test('les identifiants des URL arrivent masqués dans le fichier', () async {
      openJournal(file);
      log('GET $host/player_api.php?username=$user&password=$pass');
      log('Lecture', error: '$host/movie/$user/$pass/42.mkv');
      await flushJournal();
      final text = file.readAsStringSync();
      expect(text, contains('username=***&password=***'));
      expect(text, contains('/movie/***/***/42.mkv'));
      expect(text, isNot(contains(user)));
      expect(text, isNot(contains(pass)));
    });

    test('les secrets connus sont masqués, même hors d\'une URL', () async {
      openJournal(file);
      log(
        'Échec pour $user',
        error: 'clé $pass refusée',
        secrets: [user, pass],
      );
      await flushJournal();
      final text = file.readAsStringSync();
      expect(text, contains('Échec pour *** : clé *** refusée'));
      expect(text, isNot(contains(pass)));
    });

    test('en-tête horodaté : version, système, ABI, TV', () async {
      openJournal(file);
      log(startLine(version: '9.9.9', television: true));
      await flushJournal();
      final line = file.readAsLinesSync().single;
      expect(line, matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3} ')));
      expect(line, contains('Démarrage : CouchPlay 9.9.9'));
      expect(line, contains(Platform.operatingSystem));
      expect(line, contains('${Abi.current()}'));
      expect(line, endsWith(', TV'));
    });

    test('en-tête : téléphone', () {
      expect(
        startLine(version: '9.9.9', television: false, phone: true),
        endsWith(', téléphone'),
      );
      expect(
        startLine(version: '9.9.9', television: false),
        isNot(contains('téléphone')),
      );
    });

    test('pile tronquée et masquée', () async {
      openJournal(file);
      final stack = StackTrace.fromString(
        [
          '#0 get ($host/movie/$user/$pass/42.mkv)',
          for (var i = 1; i < 30; i++) '#$i frame$i',
        ].join('\n'),
      );
      log('Erreur non rattrapée', error: 'boom', stack: stack);
      await flushJournal();
      final text = file.readAsStringSync();
      expect(text, contains('Erreur non rattrapée : boom'));
      expect(text, contains('#0 get ($host/movie/***/***/42.mkv)'));
      expect(text, contains('#11 frame11'));
      expect(text, isNot(contains('#12 frame12')));
      expect(text, contains('…'));
      expect(text, isNot(contains(pass)));
    });

    test('une entrée trop longue est coupée', () async {
      openJournal(file);
      log('x' * 10000);
      await flushJournal();
      expect(file.lengthSync(), lessThan(4100));
    });

    test('une entrée répétée est comptée, pas réécrite', () async {
      openJournal(file);
      for (var i = 0; i < 5; i++) {
        log('même erreur');
      }
      log('autre');
      await flushJournal();
      final lines = file.readAsLinesSync();
      expect(lines, hasLength(3));
      expect(lines[0], endsWith(' même erreur'));
      expect(lines[1], endsWith(' (entrée précédente répétée 4 fois)'));
      expect(lines[2], endsWith(' autre'));
    });

    test(
      'au-delà du plafond, le fichier passe en .1 (une seule copie)',
      () async {
        openJournal(file, maxBytes: 200);
        for (var i = 0; i < 20; i++) {
          log('ligne $i ${'-' * 40}');
          await flushJournal();
        }
        final old = File('${file.path}.1');
        expect(old.existsSync(), isTrue);
        expect(file.lengthSync(), lessThanOrEqualTo(200));
        expect(old.lengthSync(), lessThanOrEqualTo(200));
        expect(dir.listSync(), hasLength(2));
        expect(file.readAsStringSync(), contains('ligne 19 '));
        expect(old.readAsStringSync(), isNot(contains('ligne 0 ')));
        final tail = await readJournalTail();
        expect(tail.last, contains('ligne 19 '));
        expect(tail.first, isNot(contains('ligne 0 ')));
      },
    );

    test('la lecture rend la fin, à partir d\'un début de ligne', () async {
      openJournal(file);
      for (var i = 0; i < 100; i++) {
        log('ligne $i');
      }
      final tail = await readJournalTail(maxBytes: 300);
      expect(tail.last, endsWith(' ligne 99'));
      expect(tail.length, lessThan(100));
      expect(
        tail,
        everyElement(matches(RegExp(r'^\d{4}-\d\d-\d\dT.* ligne \d+$'))),
      );
    });

    test('un échec passager ne coupe pas le journal', () async {
      // Dossier absent le temps d'une écriture (disque plein un instant,
      // fichier verrouillé par un antivirus) : la ligne est perdue, pas les
      // suivantes.
      final later = Directory('${dir.path}${Platform.pathSeparator}absent');
      final journal = File('${later.path}${Platform.pathSeparator}x.log');
      openJournal(journal);
      log('perdu');
      await flushJournal();
      expect(journal.existsSync(), isFalse);

      later.createSync();
      log('arrive');
      await flushJournal();
      final text = journal.readAsStringSync();
      expect(text, contains(' arrive'));
      expect(text, isNot(contains('perdu')));
    });

    test('une ligne de continuation ne peut pas imiter une entrée', () async {
      openJournal(file);
      const forged = '2026-01-01T00:00:00.000 Démarrage : faux';
      log('a\n$forged\r$forged\r\n$forged');
      // Masqué avant le préfixe : un secret coupé par un saut de ligne.
      log('clé ab\ncd fin', secrets: ['ab\ncd']);
      await flushJournal();
      final text = file.readAsStringSync();
      final lines = text.split(RegExp(r'\r\n?|\n'))..removeLast();
      final entry = RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3} ');
      expect(lines.where(entry.hasMatch), hasLength(2));
      expect(lines.where((l) => l.startsWith(forged)), isEmpty);
      expect(lines.where((l) => l == '  | $forged'), hasLength(3));
      expect(text, contains(' clé *** fin'));
      expect(text, isNot(contains('cd')));
      final tail = await readJournalTail();
      expect(tail.where(entry.hasMatch), hasLength(2));
    });

    test('flushJournal écrit le compte d\'une entrée répétée', () async {
      openJournal(file);
      for (var i = 0; i < 3; i++) {
        log('même erreur');
      }
      await flushJournal();
      final lines = file.readAsLinesSync();
      expect(lines, hasLength(2));
      expect(lines[1], endsWith(' (entrée précédente répétée 2 fois)'));
    });

    test('un lot trop gros perd ses entrées les plus anciennes', () async {
      openJournal(file, maxBatch: 300);
      // Écrites d'un trait : toutes dans le même lot.
      for (var i = 0; i < 20; i++) {
        log('entrée $i ${'-' * 20}');
      }
      await flushJournal();
      final text = file.readAsStringSync();
      expect(text.length, lessThan(400));
      expect(text, contains(' entrée 19 '));
      expect(text, isNot(contains(' entrée 0 ')));
      final lost = RegExp(r' \((\d+) entrées perdues\)').firstMatch(text);
      expect(lost, isNotNull);
      final kept = RegExp(r' entrée \d+ ').allMatches(text).length;
      expect(int.parse(lost![1]!) + kept, 20);
    });

    test('les entrées d\'avant l\'ouverture suivent l\'en-tête', () async {
      holdLogUntilJournal(maxChars: 300);
      for (var i = 0; i < 20; i++) {
        log('Comptes illisibles $i');
      }
      openJournal(file, header: startLine(version: '9.9.9', television: false));
      await flushJournal();
      final lines = file.readAsLinesSync();
      expect(lines.first, contains('Démarrage : CouchPlay 9.9.9'));
      expect(lines[1], matches(RegExp(r' \(\d+ entrées perdues\)$')));
      expect(lines.last, endsWith(' Comptes illisibles 19'));
      expect(file.readAsStringSync(), isNot(contains(' illisibles 0\n')));
    });

    test('closeJournal oublie les entrées gardées', () async {
      holdLogUntilJournal();
      log('jamais écrite');
      await closeJournal();
      openJournal(file);
      log('après');
      await flushJournal();
      expect(file.readAsStringSync(), isNot(contains('jamais')));
    });

    test(
      'Linux : fichier et copie lisibles par le seul propriétaire',
      () async {
        openJournal(file, maxBytes: 200);
        for (var i = 0; i < 6; i++) {
          log('ligne $i ${'-' * 40}');
          await flushJournal();
        }
        for (final f in [file, File('${file.path}.1')]) {
          final mode = (await f.stat()).mode & 0x1FF;
          expect(mode.toRadixString(8), '600', reason: f.path);
        }
      },
      skip: !Platform.isLinux,
    );

    test('3 échecs de suite coupent le journal, sans lever', () async {
      final later = Directory('${dir.path}${Platform.pathSeparator}absent');
      final journal = File('${later.path}${Platform.pathSeparator}x.log');
      openJournal(journal);
      for (var i = 0; i < 3; i++) {
        log('perdu $i');
        await flushJournal();
      }
      later.createSync();
      log('coupé');
      await flushJournal();
      expect(journal.existsSync(), isFalse);
    });
  });
}
