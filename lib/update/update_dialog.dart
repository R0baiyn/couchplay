import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../logging.dart';
import 'updater.dart';

/// « Version X disponible » et ses notes. « Mettre à jour » l'installe tout
/// de suite et relance l'app ; « Plus tard » la télécharge en fond et
/// l'installe à la fermeture.
Future<void> showUpdateDialog(
  BuildContext context,
  Updater updater,
  Update update,
) async {
  final now = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Version ${update.version} disponible'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [
            if (update.notes.isNotEmpty) Text(update.notes),
            Text(
              'Plus tard : elle s\'installera à la fermeture de CouchPlay.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Mettre à jour'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (now != true) {
    // Fermer la fenêtre sans choisir vaut « Plus tard ». Le message dit quand
    // on peut fermer l'app sans perdre le téléchargement.
    unawaited(
      updater
          .prepare(update)
          .then<void>(
            (_) => messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Mise à jour prête : elle s\'installera à la fermeture de '
                  'CouchPlay.',
                ),
              ),
            ),
            onError: (Object e) =>
                log('Préparation de la mise à jour', error: e.runtimeType),
          ),
    );
    return;
  }
  final navigator = Navigator.of(context);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Mise à jour'),
          content: ValueListenableBuilder(
            valueListenable: updater.progress,
            builder: (context, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 16,
              children: [
                LinearProgressIndicator(value: value),
                Text('Téléchargement : ${(value * 100).round()} %'),
              ],
            ),
          ),
          actions: [
            // Une connexion lente mais vivante ne bloque jamais l'app.
            TextButton(onPressed: updater.cancel, child: const Text('Annuler')),
          ],
        ),
      ),
    ),
  );
  try {
    await updater.installNow(update);
  } on Object catch (e) {
    // Toute erreur, pas seulement une Exception : la fenêtre de progression
    // ne se ferme pas seule, elle bloquerait l'app.
    log('Mise à jour', error: e.runtimeType);
    navigator.pop();
    final cancelled = e is DioException && CancelToken.isCancel(e);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          cancelled
              ? 'Mise à jour annulée.'
              : 'La mise à jour a échoué. Réessaie plus tard.',
        ),
      ),
    );
  }
}
