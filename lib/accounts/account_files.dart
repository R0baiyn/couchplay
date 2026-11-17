import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging.dart';
import 'account.dart';

/// Dossiers des données de chaque compte : `<support de l'app>/accounts/<id>/`
/// (règle 6). Cache du catalogue et bibliothèque y vivront.
final class AccountFiles {
  const AccountFiles(this.root);

  /// Le dossier `accounts`.
  final Directory root;

  Directory of(String accountId) {
    if (!isValidAccountId(accountId)) {
      throw ArgumentError.value(
        accountId,
        'accountId',
        'id de compte invalide',
      );
    }
    return Directory('${root.path}${Platform.pathSeparator}$accountId');
  }

  /// Chemin de [name] (fichier ou dossier) dans le dossier du compte.
  String path(String accountId, String name) =>
      '${of(accountId).path}${Platform.pathSeparator}$name';

  /// Efface toutes les données du compte, s'il en a.
  Future<void> delete(String accountId) async {
    final directory = of(accountId);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  /// Crée le dossier du compte. Seul l'enregistrement d'un compte le crée :
  /// le cache n'en crée jamais, pour qu'une écriture en retard ne fasse pas
  /// revenir le dossier d'un compte supprimé.
  Future<void> create(String accountId) async {
    try {
      await of(accountId).create(recursive: true);
    } on FileSystemException catch (e) {
      log('Dossier du compte non créé', error: e.osError?.errorCode);
    }
  }

  /// Met les dossiers en accord avec les comptes : crée ceux qui manquent,
  /// efface ceux des comptes disparus (suppression interrompue, fichier
  /// verrouillé au moment de la suppression).
  Future<void> sync(Set<String> accountIds) async {
    try {
      for (final id in accountIds) {
        await of(id).create(recursive: true);
      }
      // Premier lancement, sans compte : rien à ranger.
      if (!await root.exists()) return;
      await for (final entry in root.list()) {
        final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
        if (entry is Directory && !accountIds.contains(name)) {
          await entry.delete(recursive: true);
        }
      }
    } on FileSystemException catch (e) {
      log('Dossiers orphelins non effacés', error: e.osError?.errorCode);
    }
  }
}

/// Écrit [text] dans [path] de façon atomique : fichier temporaire au nom
/// unique, puis renommage. Seule écriture des fichiers de données d'un
/// compte (cache du catalogue, bibliothèque, réglages). Synchrone : appelée
/// dans un isolate.
///
/// Le dossier n'est jamais créé ici ([AccountFiles.create]) : s'il a
/// disparu, le compte vient d'être supprimé, et une écriture en retard ne
/// doit pas le faire revenir. Rend l'erreur (disque plein, fichier
/// verrouillé) au lieu de la lever, `null` si tout est écrit.
FileSystemException? writeAtomically(String path, String text) {
  final temp = File('$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
  try {
    temp.writeAsStringSync(text, flush: true);
    temp.renameSync(path);
    return null;
  } on FileSystemException catch (e) {
    try {
      if (temp.existsSync()) temp.deleteSync();
    } on FileSystemException {
      // Rien de plus à faire : un fichier temporaire oublié ne gêne pas.
    }
    return e;
  }
}

/// Écritures d'un fichier de données d'un compte, l'une après l'autre (la
/// dernière demandée reste), chacune atomique ([writeAtomically]) et hors du
/// thread de l'interface. Un échec est loggé sans lever : l'état reste en
/// mémoire pour la session.
final class SerialFileWriter {
  SerialFileWriter({required this.failure});

  /// Message des logs en cas d'échec : « Bibliothèque non écrite »…
  final String failure;

  Future<void> _pending = Future.value();

  /// Écritures pas encore faites, toutes files confondues.
  static final _inFlight = <Future<void>>{};

  Future<void> write(File file, String text) {
    final done = _pending = _pending.then((_) async {
      final error = await _writeInIsolate(file.path, text);
      if (error != null) log(failure, error: error.osError?.errorCode);
    });
    _inFlight.add(done);
    return done.whenComplete(() => _inFlight.remove(done));
  }

  /// Attend toutes les écritures demandées jusqu'ici : avant de quitter
  /// l'app sans passer par sa fermeture normale.
  static Future<void> flushAll() => Future.wait(_inFlight.toList());
}

// Fonction de premier niveau : l'isolate ne reçoit que ses paramètres.
Future<FileSystemException?> _writeInIsolate(String path, String text) =>
    Isolate.run(() => writeAtomically(path, text));

/// Créé dans `main()` à partir du dossier de support, puis injecté.
final accountFilesProvider = Provider<AccountFiles>(
  (ref) => throw UnimplementedError('accountFilesProvider doit être surchargé'),
);

/// Dossiers des vidéos téléchargées de chaque compte :
/// `<dossier local de l'app>/downloads/<id>/`, créé dans `main()` (voir
/// `downloadsRoot`). `null` (tests) : pas de téléchargement.
final downloadFilesProvider = Provider<AccountFiles?>((ref) => null);

/// Téléchargements de chaque compte, vus de sa suppression
/// ([whileDownloadsReleased]). Tenus par la file des téléchargements, hors
/// de ses providers (ils dépendent du compte actif) ; déclarés ici, sous
/// elle, pour que la suppression d'un compte n'importe pas la file (D-051).
/// Écrits seulement par `DownloadsNotifier` et [whileDownloadsReleased].
abstract final class AccountDownloads {
  /// Comptes en cours de suppression : rien ne repart.
  static final released = <String>{};

  /// Arrêt du téléchargement en cours de chaque compte, pour
  /// [whileDownloadsReleased] et pour la construction suivante du même
  /// compte.
  static final running = <String, Future<void> Function()>{};
}

/// Suppression du compte [accountId] : arrête d'abord son téléchargement en
/// cours et attend que son fichier soit fermé, puis lance [delete] (Windows
/// n'efface pas un fichier ouvert). Rien ne repart pour ce compte pendant
/// ce temps.
Future<void> whileDownloadsReleased(
  String accountId,
  Future<void> Function() delete,
) async {
  AccountDownloads.released.add(accountId);
  try {
    await AccountDownloads.running[accountId]?.call();
    await delete();
  } finally {
    AccountDownloads.released.remove(accountId);
  }
}
