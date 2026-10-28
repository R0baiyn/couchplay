import 'dart:async';

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
  if (now != true) {
    // Fermer la fenêtre sans choisir vaut « Plus tard ».
    unawaited(
      updater
          .prepare(update)
          .then<void>(
            (_) {},
            onError: (Object e) =>
                log('Préparation de la mise à jour', error: e.runtimeType),
          ),
    );
    return;
  }
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
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
        ),
      ),
    ),
  );
  try {
    await updater.installNow(update);
  } on Exception catch (e) {
    log('Mise à jour', error: e.runtimeType);
    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('La mise à jour a échoué. Réessaie plus tard.'),
      ),
    );
  }
}
