import 'package:flutter/material.dart';

import '../server/server_client.dart';

/// Message d'erreur et bouton « Réessayer ».
///
/// Seuls les messages du client serveur s'affichent : une autre erreur
/// pourrait contenir une URL avec identifiants.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            Text(
              error is ServerException ? error.message : 'Erreur inattendue',
              textAlign: TextAlign.center,
            ),
            FilledButton(
              autofocus: true,
              onPressed: onRetry,
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandeau des données affichées depuis un cache, faute de réseau.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.savedAt});

  final DateTime? savedAt;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = savedAt?.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final when = date == null
        ? ''
        : ' du ${two(date.day)}/${two(date.month)} à '
              '${two(date.hour)}h${two(date.minute)}';
    return Material(
      color: colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          spacing: 12,
          children: [
            Icon(Icons.cloud_off, color: colors.onTertiaryContainer),
            Expanded(
              child: Text(
                'Hors ligne : catalogue enregistré$when',
                style: TextStyle(color: colors.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
