import 'package:flutter/material.dart';

import '../format.dart';
import '../server/server_client.dart';

/// Message d'erreur, bouton « Réessayer » et, avec [onExit], « Retour ».
///
/// Seuls les messages du client serveur s'affichent : une autre erreur
/// pourrait contenir une URL avec identifiants. [message], s'il est donné,
/// remplace celui de [error].
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    this.error,
    this.message,
    required this.onRetry,
    this.onExit,
  });

  final Object? error;
  final String? message;
  final VoidCallback onRetry;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    final onExit = this.onExit;
    final retry = FilledButton(
      key: const ValueKey('catalog.errorRetry'),
      autofocus: true,
      onPressed: onRetry,
      child: const Text('Réessayer'),
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            Text(
              message ??
                  (error is ServerException
                      ? error.message
                      : 'Erreur inattendue'),
              textAlign: TextAlign.center,
            ),
            if (onExit == null)
              retry
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  OutlinedButton(
                    key: const ValueKey('catalog.errorExit'),
                    onPressed: onExit,
                    child: const Text('Retour'),
                  ),
                  retry,
                ],
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
    final when = date == null
        ? ''
        : ' du ${twoDigits(date.day)}/${twoDigits(date.month)} à '
              '${twoDigits(date.hour)}h${twoDigits(date.minute)}';
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
