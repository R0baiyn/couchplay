import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../server/models.dart';
import '../server/server_client.dart';
import 'account.dart';
import 'account_store.dart';

/// Fabrique le client d'un compte. Remplacée dans les tests par un faux serveur.
final serverClientFactoryProvider = Provider<ServerClient Function(Account)>(
  (ref) =>
      (account) => ServerClient(
        host: account.host,
        username: account.username,
        password: account.password,
        userAgent: account.userAgent,
      ),
);

/// État de l'abonnement du compte actif, rechargé quand le compte change.
final accountInfoProvider = FutureProvider.autoDispose<AccountInfo>(
  (ref) {
    final account = ref.watch(activeAccountProvider);
    if (account == null) throw StateError('Aucun compte actif');
    return ref.watch(serverClientFactoryProvider)(account).accountInfo();
  },
  // Pas de nouvelle tentative automatique : des identifiants refusés le
  // resteraient, et l'écran propose « Réessayer ».
  retry: (_, _) => null,
);
