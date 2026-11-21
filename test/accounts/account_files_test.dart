import 'dart:async';
import 'dart:io';

import 'package:couchplay/accounts/account_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('couchplay_files_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('écrit le fichier entier, sans fichier temporaire laissé', () {
    final path = '${root.path}/library.json';
    File(path).writeAsStringSync('ancien');

    expect(writeAtomically(path, 'nouveau'), isNull);
    expect(File(path).readAsStringSync(), 'nouveau');
    expect(root.listSync(), hasLength(1));
  });

  test('dossier disparu : erreur rendue, dossier pas recréé', () {
    final gone = '${root.path}/compte-supprime';

    expect(writeAtomically('$gone/library.json', '{}'), isNotNull);
    expect(Directory(gone).existsSync(), isFalse);
  });

  test('les écritures en série gardent la dernière', () async {
    final file = File('${root.path}/catalog_settings.json');
    final writer = SerialFileWriter(failure: 'non écrit');

    await Future.wait([for (var i = 0; i < 5; i++) writer.write(file, '$i')]);
    expect(file.readAsStringSync(), '4');
    expect(root.listSync(), hasLength(1));
  });

  test('flushAll attend les écritures de toutes les files', () async {
    final first = File('${root.path}/library.json');
    final second = File('${root.path}/settings.json');
    unawaited(SerialFileWriter(failure: 'non écrit').write(first, 'a'));
    unawaited(SerialFileWriter(failure: 'non écrit').write(second, 'b'));

    await SerialFileWriter.flushAll();
    expect(first.readAsStringSync(), 'a');
    expect(second.readAsStringSync(), 'b');
  });

  test('flushAll accepte un onTimeout qui ne rend rien', () async {
    // Régression : flushAll rendait le Future<List<void>> de Future.wait, et
    // timeout levait une TypeError sur ce onTimeout avant tout délai.
    await SerialFileWriter.flushAll().timeout(
      const Duration(seconds: 1),
      onTimeout: () {},
    );
  });

  test('une écriture qui lève ne bloque ni la suivante ni flushAll', () async {
    final file = File('${root.path}/library.json');
    var calls = 0;
    final writer = SerialFileWriter(
      failure: 'non écrit',
      writeFile: (path, text) async {
        if (calls++ == 0) throw StateError('isolate');
        return writeAtomically(path, text);
      },
    );

    final first = writer.write(file, 'a');
    final second = writer.write(file, 'b');
    await SerialFileWriter.flushAll();
    await first;
    await second;
    expect(file.readAsStringSync(), 'b');
  });

  test('path : un fichier dans le dossier du compte', () {
    final files = AccountFiles(root);
    expect(
      files.path('compte', 'library.json'),
      '${files.of('compte').path}${Platform.pathSeparator}library.json',
    );
    expect(() => files.path('../x', 'library.json'), throwsArgumentError);
  });
}
