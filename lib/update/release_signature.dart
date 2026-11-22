import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

// Sans Flutter : ce fichier sert aussi à `tool/sign_release.dart`, lancé par
// `dart run` dans la CI.

/// Liste des SHA-256 des fichiers d'une release, publiée avec eux.
const sumsName = 'SHA256SUMS';

/// Signature ed25519 de [sumsName], en base64 sur une ligne.
const signatureName = 'SHA256SUMS.sig';

/// Clé publique ed25519 des releases, en base64. Sa clé privée est le secret
/// `RELEASE_SIGNING_KEY` de l'environnement `release` de la CI, qui signe
/// chaque release : la changer ici rend les releases déjà signées
/// invérifiables par cette version de l'app.
const releasePublicKey = '7wL3Xm1OdsW1QHD3WZxNKgAQj3eXwziVi4+GLZ6mh2M=';

/// [releasePublicKey] décodée.
final releaseKey = decodeKey(releasePublicKey, keyLength)!;

/// Les fichiers [sumsName] et [signatureName] ne sont pas dans la liste.
bool isSignatureFile(String name) => name.startsWith(sumsName);

/// Nom de fichier accepté dans la liste : pas de chemin, pas d'espace.
bool isValidFileName(String name) => _fileName.hasMatch(name);

final _fileName = RegExp(r'^[A-Za-z0-9._+-]+$');

final _sumLine = RegExp(r'^([0-9a-f]{64})  (.+)$');

/// SHA-256 de [file] en hexadécimal minuscule, lu en flux.
Future<String> sha256OfFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Texte de [sumsName], au format de `sha256sum` : `<hex>  <nom>`, une ligne
/// par fichier, triées par nom. `sha256sum -c SHA256SUMS` le relit.
String formatSums(Map<String, String> sums) {
  final names = sums.keys.toList()..sort();
  return [for (final name in names) '${sums[name]}  $name\n'].join();
}

/// Les sommes de [text], par nom de fichier. `null` si une ligne est mal
/// formée, si un nom revient deux fois ou si la liste est vide : une liste
/// douteuse ne vaut rien, même signée.
Map<String, String>? parseSums(String text) {
  if (!text.endsWith('\n')) return null;
  final sums = <String, String>{};
  for (final line in text.substring(0, text.length - 1).split('\n')) {
    final match = _sumLine.firstMatch(line);
    if (match == null) return null;
    final name = match[2]!;
    if (!isValidFileName(name) || sums.containsKey(name)) return null;
    sums[name] = match[1]!;
  }
  return sums;
}

/// Clé de [length] octets écrite en base64 dans [text] (espaces et fin de
/// ligne autour ignorés). `null` si ce n'en est pas une.
Uint8List? decodeKey(String text, int length) {
  try {
    final bytes = base64.decode(text.trim());
    return bytes.length == length ? bytes : null;
  } on FormatException {
    return null;
  }
}

/// Taille de la graine de la clé privée, de la clé publique.
const keyLength = 32;

const _signatureLength = 64;

final _ed25519 = DartEd25519();

/// Clé publique de la clé privée [seed].
Future<Uint8List> publicKeyOf(List<int> seed) async {
  final pair = await _ed25519.newKeyPairFromSeed(seed);
  return Uint8List.fromList((await pair.extractPublicKey()).bytes);
}

/// Signature de [message] par la clé privée [seed], en base64.
Future<String> signBytes(List<int> message, List<int> seed) async {
  final pair = await _ed25519.newKeyPairFromSeed(seed);
  final signature = await _ed25519.sign(message, keyPair: pair);
  return base64.encode(signature.bytes);
}

/// [signature] (base64, texte de [signatureName]) est celle de [message]
/// par la clé publique [publicKey]. Toute forme inattendue donne `false`.
Future<bool> verifyBytes(
  List<int> message,
  String signature,
  List<int> publicKey,
) async {
  final bytes = decodeKey(signature, _signatureLength);
  if (bytes == null || publicKey.length != keyLength) return false;
  return _ed25519.verify(
    message,
    signature: Signature(
      bytes,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
    ),
  );
}

/// Les sommes de [sums] si [signature] est sa signature par [publicKey] et
/// que la liste est bien formée, sinon `null`.
Future<Map<String, String>?> verifiedSums(
  List<int> sums,
  String signature,
  List<int> publicKey,
) async {
  if (!await verifyBytes(sums, signature, publicKey)) return null;
  try {
    return parseSums(utf8.decode(sums));
  } on FormatException {
    return null;
  }
}

/// La somme de [file] (64 chiffres hexadécimaux minuscules) s'il est,
/// publié sous le nom [name], dans la liste [sums] signée par [signature] et
/// y a sa somme exacte ; sinon `null`. [publicKey] : [releaseKey] par défaut.
Future<String?> signedSum({
  required List<int> sums,
  required String signature,
  required String name,
  required File file,
  List<int>? publicKey,
}) async {
  final listed = await verifiedSums(sums, signature, publicKey ?? releaseKey);
  final expected = listed?[name];
  return expected != null && await sha256OfFile(file) == expected
      ? expected
      : null;
}
