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

  /// Efface les dossiers des comptes qui n'existent plus : suppression
  /// interrompue, ou fichier verrouillé au moment de la suppression.
  Future<void> removeOrphans(Set<String> accountIds) async {
    try {
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
