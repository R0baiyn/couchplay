import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/logging.dart';
import 'package:couchplay/update/hidden_process.dart';
import 'package:couchplay/update/release_signature.dart';
import 'package:couchplay/update/updater.dart';
import 'package:couchplay/update/windows_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('couchplay_maj_'));
  tearDown(() async {
    // Écritures statiques : finies avant le test suivant et l'effacement.
    await SerialFileWriter.flushAll();
    await closeJournal();
    root.deleteSync(recursive: true);
  });

  test(
    'installNow demande la relance, attend les écritures puis quitte',
    () async {
      final settings = File('${root.path}\\settings.json');
      final journal = File('${root.path}\\couchplay.log');
      openJournal(journal);
      final codes = <int>[];
      String? writtenAtExit;
      String? journalAtExit;
      final installer = WindowsInstaller(
        portable: false,
        appDir: root,
        workDir: root,
        exit: (code) {
          codes.add(code);
          writtenAtExit = settings.existsSync()
              ? settings.readAsStringSync()
              : null;
          journalAtExit = journal.existsSync()
              ? journal.readAsStringSync()
              : null;
        },
      );
      unawaited(
        SerialFileWriter(failure: 'non écrit').write(settings, '{"a":1}'),
      );

      await installer.installNow();

      expect(File('${root.path}\\relaunch').existsSync(), isTrue);
      expect(codes, [0]);
      expect(writtenAtExit, '{"a":1}');
      // Le journal aussi est écrit avant la sortie (D-058).
      expect(
        journalAtExit,
        contains('Fermeture pour installer la mise à jour'),
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'installNow quitte même si le marqueur de relance est impossible',
    () async {
      final codes = <int>[];
      final installer = WindowsInstaller(
        portable: false,
        appDir: root,
        // Dossier absent : `create()` lève un FileSystemException.
        workDir: Directory('${root.path}\\absent'),
        exit: codes.add,
      );

      await installer.installNow();

      expect(codes, [0]);
    },
    skip: !Platform.isWindows,
  );

  test('prepared sans somme vérifiée : rien n\'est lancé', () async {
    final installer = WindowsInstaller(
      portable: true,
      appDir: root,
      workDir: root,
    );
    final package = File('${root.path}\\update.zip')..writeAsStringSync('z');
    final update = Update(version: '9.9.9', notes: '', asset: Uri(), size: 1);
    for (final sum in [null, '', 'ABC', '%TEMP%']) {
      await expectLater(
        installer.prepared(update, package, sum),
        throwsArgumentError,
      );
    }
    expect(File('${root.path}\\install.cmd').existsSync(), isFalse);
  });

  group('script d\'installation réel, branche zip', () {
    late Directory work;
    late Directory app;
    late File package;

    setUp(() {
      // Seul un dossier de ce nom est effacé par le script.
      work = Directory('${root.path}\\couchplay-update')..createSync();
      app = Directory('${root.path}\\app')..createSync();
      package = File('${work.path}\\update.zip');
    });

    /// Zip valide de [files] (nom → contenu), écrit dans [target].
    Future<void> zip(File target, Map<String, String> files) async {
      final source = Directory('${root.path}\\zip-source');
      if (source.existsSync()) source.deleteSync(recursive: true);
      for (final MapEntry(:key, :value) in files.entries) {
        File('${source.path}\\$key')
          ..createSync(recursive: true)
          ..writeAsStringSync(value);
      }
      final tar = '${Platform.environment['SystemRoot']}\\System32\\tar.exe';
      final result = await Process.run(tar, [
        '-a',
        '-cf',
        target.path,
        '-C',
        source.path,
        '.',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    /// Lance le script comme `prepared`, avec un PID mort et un exe absent,
    /// puis attend qu'il ait effacé son dossier.
    Future<void> runScript(String sum) async {
      final script = File('${work.path}\\install.cmd');
      await script.writeAsString(
        LineSplitter.split(installScript).join('\r\n'),
      );
      final dead = (await Process.run('cmd', ['/c', 'exit'])).pid;
      startHiddenScript(script.path, [
        '$dead',
        package.path,
        app.path,
        '${app.path}\\absent-couchplay.exe',
        '${work.path}\\relaunch',
        sum,
      ]);
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (work.existsSync()) {
        if (DateTime.now().isAfter(deadline)) fail('Script non terminé');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    test('bon paquet : les fichiers sont copiés', () async {
      await zip(package, {
        'nouveau.txt': 'v2',
        'data\\flutter_assets\\a.txt': 'v2',
      });

      await runScript(await sha256OfFile(package));

      expect(File('${app.path}\\nouveau.txt').readAsStringSync(), 'v2');
      expect(
        File('${app.path}\\data\\flutter_assets\\a.txt').existsSync(),
        isTrue,
      );
    }, skip: !Platform.isWindows);

    test('paquet remplacé après la vérification : rien n\'est copié', () async {
      await zip(package, {'nouveau.txt': 'v2'});
      final verified = await sha256OfFile(package);
      // Un autre zip, valide : seule la somme peut l'arrêter.
      await zip(package, {'autre.txt': 'piege'});

      await runScript(verified);

      expect(app.listSync(), isEmpty);
    }, skip: !Platform.isWindows);
  });

  test('installNow quitte même si une écriture en file échoue', () async {
    final codes = <int>[];
    final installer = WindowsInstaller(
      portable: false,
      appDir: root,
      workDir: root,
      exit: codes.add,
    );
    // Une erreur autre qu'un FileSystemException (isolate impossible à
    // lancer, par exemple).
    final failing = SerialFileWriter(
      failure: 'non écrit',
      writeFile: (path, text) async => throw StateError('isolate'),
    );
    unawaited(failing.write(File('${root.path}\\library.json'), '{}'));

    await installer.installNow();

    expect(codes, [0]);
  }, skip: !Platform.isWindows);
}
