import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/status_views.dart';
import '../focus_ring.dart';
import '../format.dart';
import '../server/models.dart';
import 'account_store.dart';
import 'server_session.dart';

/// État de l'abonnement du compte actif, ouvert depuis les réglages.
class AccountStatusScreen extends ConsumerWidget {
  const AccountStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(activeAccountProvider.select((a) => a?.name));
    final info = ref.watch(accountInfoProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(name == null ? 'Abonnement' : 'Abonnement · $name'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: info.isLoading
                ? null
                : () => ref.invalidate(accountInfoProvider),
          ),
        ],
      ),
      body: Center(
        child: switch (info) {
          // En premier : un rechargement garde l'ancienne valeur ou erreur.
          AsyncValue(isLoading: true) => const CircularProgressIndicator(),
          AsyncData(:final value) => _Details(value),
          AsyncError(:final error) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(accountInfoProvider),
          ),
          _ => const CircularProgressIndicator(),
        },
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details(this.info);

  final AccountInfo info;

  static const _statuses = {
    'active': 'Actif',
    'expired': 'Expiré',
    'banned': 'Banni',
    'disabled': 'Désactivé',
  };

  @override
  Widget build(BuildContext context) {
    final status = _statuses[info.status.toLowerCase()] ?? info.status;
    final rows = <(String, String)>[
      ('Abonnement', info.isTrial ? '$status (essai)' : status),
      (
        'Expiration',
        info.expiresAt == null ? 'Aucune' : formatDate(info.expiresAt!),
      ),
      (
        'Connexions',
        '${info.activeConnections ?? '?'} en cours sur '
            '${info.maxConnections ?? '?'} autorisée(s)',
      ),
    ];
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Card(
        margin: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, value) in rows)
              ListTile(
                title: FocusRing(
                  child: Text(label, style: theme.textTheme.labelLarge),
                ),
                subtitle: Text(value, style: theme.textTheme.bodyLarge),
              ),
          ],
        ),
      ),
    );
  }
}
