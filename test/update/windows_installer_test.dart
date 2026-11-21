import 'dart:async';
import 'dart:io';

import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/update/windows_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('couchplay_maj_'));
  tearDown(() async {
    // Écritures statiques : finies avant le test suivant et l'effacement.
    await SerialFileWriter.flushAll();
    root.deleteSync(recursive: true);
  });

  test(
    'installNow demande la relance, attend les écritures puis quitte',
    () async {
      final settings = File('${root.path}\\settings.json');
      final codes = <int>[];
      String? writtenAtExit;
      final installer = WindowsInstaller(
        portable: false,
        appDir: root,
        workDir: root,
        exit: (code) {
          codes.add(code);
          writtenAtExit = settings.existsSync()
              ? settings.readAsStringSync()
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
    },
    skip: !Platform.isWindows,
  );
}
