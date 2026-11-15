import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:couchplay/update/release_signature.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late File file;
  late List<int> seed;
  late List<int> publicKey;
  late List<int> sums;
  late String signature;
  const name = 'couchplay-1.0.0-windows-setup.exe';

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('release_signature_test');
    file = File('${temp.path}/update.exe')..writeAsStringSync('exe');
    // Clé de test tirée à chaque exécution, jamais écrite en dur.
    final random = Random.secure();
    seed = [for (var i = 0; i < keyLength; i++) random.nextInt(256)];
    publicKey = await publicKeyOf(seed);
    sums = utf8.encode(
      formatSums({
        name: sha256.convert(utf8.encode('exe')).toString(),
        'couchplay-1.0.0-android-arm64.apk': '0' * 64,
      }),
    );
    signature = await signBytes(sums, seed);
  });

  tearDown(() => temp.delete(recursive: true));

  Future<bool> check({
    List<int>? list,
    String? sig,
    String fileName = name,
    List<int>? key,
  }) => isSignedFile(
    sums: list ?? sums,
    signature: sig ?? signature,
    name: fileName,
    file: file,
    publicKey: key ?? publicKey,
  );

  test('signature valide et bonne somme : accepté', () async {
    expect(await check(), isTrue);
  });

  test('liste modifiée après signature : refusé', () async {
    final changed = [...sums]..[0] ^= 1;
    expect(await check(list: changed), isFalse);
  });

  test('fichier absent de la liste : refusé', () async {
    expect(
      await check(fileName: 'couchplay-1.0.0-windows-portable.zip'),
      isFalse,
    );
  });

  test('somme fausse : refusé', () async {
    file.writeAsStringSync('exf');
    expect(await check(), isFalse);
  });

  test('signature absente ou illisible : refusé', () async {
    expect(await check(sig: ''), isFalse);
    expect(await check(sig: 'pas du base64'), isFalse);
    expect(await check(sig: base64.encode([1, 2, 3])), isFalse);
  });

  test('signée par une autre clé : refusé', () async {
    final other = await publicKeyOf(List.filled(keyLength, 7));
    expect(await check(key: other), isFalse);
    // Par défaut, la clé embarquée, qui n'est pas celle du test.
    expect(
      await isSignedFile(
        sums: sums,
        signature: signature,
        name: name,
        file: file,
      ),
      isFalse,
    );
  });

  test('clé embarquée lisible', () {
    expect(releaseKey, hasLength(keyLength));
  });
}
