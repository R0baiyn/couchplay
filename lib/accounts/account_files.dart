import 'dart:io';

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

/// Créé dans `main()` à partir du dossier de support, puis injecté.
final accountFilesProvider = Provider<AccountFiles>(
  (ref) => throw UnimplementedError('accountFilesProvider doit être surchargé'),
);
