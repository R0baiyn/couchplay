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

/// Client du compte actif. Recréé seulement quand ses accès changent (pas
/// quand on renomme le compte), et fermé quand il est remplacé.
final serverClientProvider = Provider.autoDispose<ServerClient?>((ref) {
  final access = ref.watch(
    activeAccountProvider.select(
      (a) => a == null
          ? null
          : (a.id, a.host, a.username, a.password, a.userAgent),
    ),
  );
  if (access == null) return null;
  final client = ref.watch(serverClientFactoryProvider)(
    ref.read(activeAccountProvider)!,
  );
  ref.onDispose(client.close);
  return client;
});

/// État de l'abonnement du compte actif, rechargé quand ses accès changent.
final accountInfoProvider = FutureProvider.autoDispose<AccountInfo>(
  (ref) {
    final client = ref.watch(serverClientProvider);
    if (client == null) throw StateError('Aucun compte actif');
    return client.accountInfo();
  },
  // Pas de nouvelle tentative automatique : des identifiants refusés le
  // resteraient, et l'écran propose « Réessayer ».
  retry: (_, _) => null,
);
