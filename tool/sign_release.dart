import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:couchplay/update/release_signature.dart';

/// Signature des fichiers d'une release.
///
/// ```
/// dart run tool/sign_release.dart keygen <fichier de clé privée>
/// dart run tool/sign_release.dart sign <dossier>
/// dart run tool/sign_release.dart verify <dossier> [--public-key <base64>]
/// ```
///
/// `keygen` écrit une nouvelle clé privée (graine ed25519 en base64) dans un
/// fichier qui n'existe pas encore, hors du dossier courant, et affiche la
/// clé publique. `sign` lit la clé privée dans la variable d'environnement
/// [keyVariable], jamais en argument, et écrit `SHA256SUMS` et
/// `SHA256SUMS.sig` dans le dossier. `verify` relit les deux et sort en
/// erreur si la signature ou une somme est fausse, ou si un fichier manque
/// ou est en trop ; sans `--public-key`, avec la clé embarquée dans l'app.
Future<void> main(List<String> args) async {
  exitCode = await run(args, environment: Platform.environment);
}

/// Variable d'environnement de la clé privée pour `sign`.
const keyVariable = 'RELEASE_SIGNING_KEY';

const _usage =
    'Usage : sign_release.dart keygen <fichier> | sign <dossier> | '
    'verify <dossier> [--public-key <base64>]';

/// Code de sortie : 0 si tout va bien, 1 si l'opération échoue, 64 si les
/// arguments sont faux.
Future<int> run(
  List<String> args, {
  required Map<String, String> environment,
  StringSink? out,
  StringSink? err,
}) async {
  out ??= stdout;
  err ??= stderr;
  try {
    switch (args) {
      case ['keygen', final path]:
        return await _keygen(File(path), out);
      case ['sign', final dir]:
        return await _sign(Directory(dir), environment[keyVariable], out);
      // Par défaut, la clé que l'app embarque : la CI vérifie ce que les
      // apps vérifieront.
      case ['verify', final dir]:
        return await _verify(Directory(dir), releaseKey, out);
      case ['verify', final dir, '--public-key', final key]:
        final publicKey = decodeKey(key, keyLength);
        if (publicKey == null) {
          err.writeln('Clé publique illisible');
          return 64;
        }
        return await _verify(Directory(dir), publicKey, out);
      default:
        err.writeln(_usage);
        return 64;
    }
  } on _Failure catch (e) {
    err.writeln(e.message);
    return 1;
  }
}

final class _Failure implements Exception {
  const _Failure(this.message);
  final String message;
}

Future<int> _keygen(File file, StringSink out) async {
  final target = _normalized(file.absolute.path);
  final here = _normalized(Directory.current.absolute.path);
  if (_isWithin(target, here) || _inGitRepository(target)) {
    throw const _Failure(
      'La clé privée doit être écrite hors du dossier courant et de tout '
      'dépôt git',
    );
  }
  if (await file.exists()) {
    throw _Failure('$target existe déjà : rien n\'est écrasé');
  }
  final random = Random.secure();
  final seed = Uint8List.fromList([
    for (var i = 0; i < keyLength; i++) random.nextInt(256),
  ]);
  await file.parent.create(recursive: true);
  // `exclusive` : un fichier créé entre-temps n'est pas écrasé non plus.
  await file.create(exclusive: true);
  // Lisible par son seul propriétaire, avant d'y écrire la clé. Sous
  // Windows, rien de simple : le fichier prend les droits de son dossier.
  if (!Platform.isWindows) {
    final chmod = await Process.run('chmod', ['600', target]);
    if (chmod.exitCode != 0) {
      await file.delete();
      throw _Failure('Droits de $target non restreints : ${chmod.stderr}');
    }
  }
  await file.writeAsString('${base64.encode(seed)}\n', flush: true);
  out.writeln('Clé privée écrite dans $target');
  out.writeln('Clé publique : ${base64.encode(await publicKeyOf(seed))}');
  return 0;
}

/// [path] sans `.` ni `..`.
String _normalized(String path) => Uri.file(path).normalizePath().toFilePath();

/// Un dossier au-dessus de [path] contient `.git` (dossier, ou fichier d'un
/// worktree) : la clé finirait dans un dépôt, peut-être poussée.
bool _inGitRepository(String path) {
  var dir = File(path).parent;
  while (true) {
    final git = '${dir.path}${Platform.pathSeparator}.git';
    if (FileSystemEntity.typeSync(git) != FileSystemEntityType.notFound) {
      return true;
    }
    final up = dir.parent;
    if (up.path == dir.path) return false;
    dir = up;
  }
}

bool _isWithin(String path, String dir) {
  String norm(String p) =>
      (Platform.isWindows ? p.toLowerCase() : p).replaceAll('\\', '/');
  final d = norm(dir).endsWith('/') ? norm(dir) : '${norm(dir)}/';
  return norm(path).startsWith(d);
}

/// Fichiers à signer de [dir], par nom : tout sauf `SHA256SUMS*`. Un
/// sous-dossier, un nom inattendu ou un dossier vide est une erreur.
Future<Map<String, File>> _releaseFiles(Directory dir) async {
  if (!await dir.exists()) throw _Failure('Dossier introuvable : ${dir.path}');
  final files = <String, File>{};
  await for (final entity in dir.list(followLinks: false)) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (entity is! File) throw _Failure('Pas un fichier : $name');
    if (isSignatureFile(name)) continue;
    if (!isValidFileName(name)) throw _Failure('Nom de fichier refusé : $name');
    files[name] = entity;
  }
  if (files.isEmpty) throw const _Failure('Aucun fichier à signer');
  return files;
}

Future<int> _sign(Directory dir, String? key, StringSink out) async {
  final seed = key == null ? null : decodeKey(key, keyLength);
  if (seed == null) {
    throw const _Failure('Clé privée absente ou illisible ($keyVariable)');
  }
  final files = await _releaseFiles(dir);
  final sums = utf8.encode(
    formatSums({
      for (final MapEntry(:key, :value) in files.entries)
        key: await sha256OfFile(value),
    }),
  );
  await File('${dir.path}/$sumsName').writeAsBytes(sums, flush: true);
  await File('${dir.path}/$signatureName')
      .writeAsString('${await signBytes(sums, seed)}\n', flush: true);
  out.writeln('${files.length} fichiers signés');
  return 0;
}

Future<int> _verify(Directory dir, List<int> publicKey, StringSink out) async {
  final files = await _releaseFiles(dir);
  final sumsFile = File('${dir.path}/$sumsName');
  final signatureFile = File('${dir.path}/$signatureName');
  if (!await sumsFile.exists() || !await signatureFile.exists()) {
    throw const _Failure('$sumsName ou $signatureName absent');
  }
  final sums = await verifiedSums(
    await sumsFile.readAsBytes(),
    await signatureFile.readAsString(),
    publicKey,
  );
  if (sums == null) throw const _Failure('Signature invalide');
  final listed = sums.keys.toSet();
  final present = files.keys.toSet();
  if (listed.difference(present) case final missing when missing.isNotEmpty) {
    throw _Failure('Fichiers absents : ${missing.join(', ')}');
  }
  if (present.difference(listed) case final extra when extra.isNotEmpty) {
    throw _Failure('Fichiers non signés : ${extra.join(', ')}');
  }
  for (final MapEntry(:key, :value) in files.entries) {
    if (await sha256OfFile(value) != sums[key]) {
      throw _Failure('Somme fausse : $key');
    }
  }
  out.writeln('${files.length} fichiers vérifiés');
  return 0;
}
