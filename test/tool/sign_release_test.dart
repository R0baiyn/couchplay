import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:couchplay/update/release_signature.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/sign_release.dart';

void main() {
  late Directory temp;
  late Directory dist;
  late String seed;
  late String publicKey;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sign_release_test');
    dist = await Directory('${temp.path}/dist').create();
    await File('${dist.path}/app-1.0.0-windows-setup.exe').writeAsString('exe');
    await File('${dist.path}/app-1.0.0-android-arm64.apk').writeAsString('apk');
    // Clé de test tirée à chaque exécution, jamais écrite en dur.
    final random = Random.secure();
    final bytes = [for (var i = 0; i < keyLength; i++) random.nextInt(256)];
    seed = base64.encode(bytes);
    publicKey = base64.encode(await publicKeyOf(bytes));
  });

  tearDown(() => temp.delete(recursive: true));

  Future<int> cli(List<String> args, {String? key}) => run(
    args,
    environment: {keyVariable: ?key},
    out: StringBuffer(),
    err: StringBuffer(),
  );

  Future<int> sign() => cli(['sign', dist.path], key: seed);
  Future<int> verify() => cli(['verify', dist.path, '--public-key', publicKey]);

  test('aller-retour : signé puis vérifié', () async {
    expect(await sign(), 0);
    expect(await verify(), 0);
    final sums = await File('${dist.path}/$sumsName').readAsString();
    expect(
      sums,
      '${sha256.convert(utf8.encode('apk'))}  app-1.0.0-android-arm64.apk\n'
      '${sha256.convert(utf8.encode('exe'))}  app-1.0.0-windows-setup.exe\n',
    );
  });

  test('un octet modifié dans un fichier : refusé', () async {
    await sign();
    await File('${dist.path}/app-1.0.0-windows-setup.exe').writeAsString('exf');
    expect(await verify(), 1);
  });

  test('signature modifiée : refusée', () async {
    await sign();
    final file = File('${dist.path}/$signatureName');
    final bytes = base64.decode((await file.readAsString()).trim());
    bytes[10] ^= 1;
    await file.writeAsString(base64.encode(bytes));
    expect(await verify(), 1);
  });

  test('liste modifiée : refusée', () async {
    await sign();
    final file = File('${dist.path}/$sumsName');
    await file.writeAsString(
      (await file.readAsString()).replaceFirst('android', 'androi_'),
    );
    expect(await verify(), 1);
  });

  test('autre clé publique : refusée', () async {
    await sign();
    final other = await publicKeyOf(List.filled(keyLength, 7));
    expect(
      await cli(['verify', dist.path, '--public-key', base64.encode(other)]),
      1,
    );
    // Sans --public-key : la clé de l'app, qui n'est pas celle du test.
    expect(await cli(['verify', dist.path]), 1);
  });

  test('fichier ajouté ou retiré après la signature : refusé', () async {
    await sign();
    final extra = File('${dist.path}/app-1.0.0-linux-x64.tar.gz');
    await extra.writeAsString('tar');
    expect(await verify(), 1);
    await extra.delete();
    await File('${dist.path}/app-1.0.0-android-arm64.apk').delete();
    expect(await verify(), 1);
  });

  test('signature absente : refusée', () async {
    await sign();
    await File('${dist.path}/$signatureName').delete();
    expect(await verify(), 1);
  });

  test('sans clé privée valide, rien n\'est signé', () async {
    expect(await cli(['sign', dist.path]), 1);
    expect(await cli(['sign', dist.path], key: 'abc'), 1);
    expect(await File('${dist.path}/$sumsName').exists(), isFalse);
  });

  test('clé privée avec fin de ligne Windows acceptée', () async {
    expect(await cli(['sign', dist.path], key: '$seed\r\n'), 0);
    expect(await verify(), 0);
  });

  test('keygen : clé utilisable, jamais d\'écrasement', () async {
    final file = File('${temp.path}/cle/release.key');
    expect(await cli(['keygen', file.path]), 0);
    final written = await file.readAsString();
    expect(decodeKey(written, keyLength), isNotNull);

    expect(await cli(['keygen', file.path]), 1);
    expect(await file.readAsString(), written);

    expect(await cli(['sign', dist.path], key: written), 0);
    final key = base64.encode(
      await publicKeyOf(decodeKey(written, keyLength)!),
    );
    expect(await cli(['verify', dist.path, '--public-key', key]), 0);
  });

  test('keygen refuse un fichier dans le dossier courant', () async {
    final file = File('${Directory.current.path}/release-test.key');
    expect(await cli(['keygen', file.path]), 1);
    expect(await file.exists(), isFalse);
  });

  for (final (kind, makeGit) in [
    ('dossier', (String p) => Directory(p).createSync()),
    (
      'fichier de worktree',
      (String p) => File(p).writeAsStringSync('gitdir: x'),
    ),
  ]) {
    test('keygen refuse un sous-dossier d\'un dépôt (.git $kind)', () async {
      final repo = Directory('${temp.path}/depot')..createSync();
      makeGit('${repo.path}/.git');
      final file = File('${repo.path}/tool/cle/release.key');
      expect(await cli(['keygen', file.path]), 1);
      expect(await file.exists(), isFalse);
      // Hors du dépôt, par un `..` : accepté.
      final outside = File('${repo.path}/tool/../../hors/release.key');
      expect(await cli(['keygen', outside.path]), 0);
    });
  }

  test('keygen : clé lisible par son seul propriétaire', () async {
    final file = File('${temp.path}/cle/release.key');
    expect(await cli(['keygen', file.path]), 0);
    expect((await file.stat()).modeString(), 'rw-------');
  }, skip: Platform.isWindows);

  test('arguments faux : code 64', () async {
    expect(await cli([]), 64);
    expect(await cli(['verify', dist.path, '--public-key']), 64);
    expect(await cli(['verify', dist.path, '--public-key', 'xx']), 64);
  });

  group('parseSums', () {
    final hex = 'a' * 64;
    test('refuse les listes douteuses', () {
      expect(parseSums(''), isNull);
      expect(parseSums('$hex  a.exe'), isNull, reason: 'sans fin de ligne');
      expect(parseSums('$hex  a.exe\n$hex  a.exe\n'), isNull);
      expect(parseSums('$hex  ../a.exe\n'), isNull);
      expect(parseSums('$hex a.exe\n'), isNull);
      expect(parseSums('${'A' * 64}  a.exe\n'), isNull);
    });
    test('lit une liste correcte', () {
      expect(parseSums('$hex  a.exe\n'), {'a.exe': hex});
    });
  });
}
