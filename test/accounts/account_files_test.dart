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
}
