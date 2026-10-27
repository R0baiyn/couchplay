import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../server/models.dart';
import '../server/server_client.dart';
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
          AsyncError(:final error) => Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: [
              Text(
                error is ServerException ? error.message : 'Erreur inattendue',
                textAlign: TextAlign.center,
              ),
              FilledButton(
                autofocus: true,
                onPressed: () => ref.invalidate(accountInfoProvider),
                child: const Text('Réessayer'),
              ),
            ],
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

  static String _date(DateTime date) {
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final status = _statuses[info.status.toLowerCase()] ?? info.status;
    final rows = <(String, String)>[
      ('Abonnement', info.isTrial ? '$status (essai)' : status),
      (
        'Expiration',
        info.expiresAt == null ? 'Aucune' : _date(info.expiresAt!),
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
                title: Text(label, style: theme.textTheme.labelLarge),
                subtitle: Text(value, style: theme.textTheme.bodyLarge),
              ),
          ],
        ),
      ),
    );
  }
}
