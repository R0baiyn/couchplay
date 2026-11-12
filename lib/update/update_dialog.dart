import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../logging.dart';
import 'linux_installer.dart';
import 'updater.dart';

/// « Version X disponible » et ses notes. « Mettre à jour » l'installe tout
/// de suite (Windows relance l'app, Android ouvre son installateur) ;
/// « Plus tard » la télécharge en fond, et elle s'installe à la fermeture
/// (Windows) ou au prochain démarrage (Android). Sous Linux, rien ne se
/// télécharge : « Ouvrir la page » ouvre la release dans le navigateur.
Future<void> showUpdateDialog(
  BuildContext context,
  Updater updater,
  Update update,
) async {
  if (updater.installer case final LinuxInstaller linux) {
    return _showLinuxDialog(context, linux, update);
  }
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
              'Plus tard : elle s\'installera ${updater.installer.later}.',
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
              SnackBar(
                content: Text(
                  'Mise à jour prête : elle s\'installera '
                  '${updater.installer.later}.',
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
    // Windows ferme l'app ici ; Android ouvre son installateur par-dessus.
    await updater.installNow(update);
    navigator.pop();
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

Future<void> _showLinuxDialog(
  BuildContext context,
  LinuxInstaller installer,
  Update update,
) async {
  final page = update.page;
  final open = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Version ${update.version} disponible'),
      content: update.notes.isEmpty
          ? null
          : SingleChildScrollView(child: Text(update.notes)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Plus tard'),
        ),
        if (page != null)
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ouvrir la page'),
          ),
      ],
    ),
  );
  if (open != true || page == null) return;
  try {
    await installer.open(page);
  } on Exception catch (e) {
    // Sans xdg-open, l'app continue : la release reste sur GitHub.
    log('Ouverture de la page de mise à jour', error: e.runtimeType);
  }
}
