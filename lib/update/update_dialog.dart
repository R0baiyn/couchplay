import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../logging.dart';
import 'updater.dart';

/// « Version X disponible » et ses notes. « Mettre à jour » l'installe tout
/// de suite (Windows relance l'app, Android ouvre son installateur) ;
/// « Plus tard » la télécharge en fond, et elle s'installe à la fermeture
/// (Windows) ou au prochain démarrage (Android). Sous Linux, rien ne se
/// télécharge : « Ouvrir la page » ouvre la release dans le navigateur.
/// Trop peu de place (Android), [confirmSpace] prévient avant tout
/// téléchargement.
Future<void> showUpdateDialog(
  BuildContext context,
  Updater updater,
  Update update,
) async {
  if (updater.installer.openPage case final openPage?) {
    return _showPageDialog(context, openPage, update);
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
            if (update.notes.isNotEmpty)
              Text(update.notes, key: const ValueKey('update.notes')),
            Text(
              'Plus tard : elle s\'installera ${updater.installer.later}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('update.later'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          key: const ValueKey('update.install'),
          autofocus: true,
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Mettre à jour'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  final short = await updater.shortfall(update);
  if (!context.mounted) return;
  if (short != null && !await confirmSpace(context, short)) return;
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
            // Réseau, GitHub ou signature refusée : rien ne s'installera,
            // l'utilisateur le sait (Q-29).
            onError: (Object e) {
              log('Préparation de la mise à jour', error: e.runtimeType);
              messenger.showSnackBar(
                const SnackBar(content: Text(_impossible)),
              );
            },
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
                LinearProgressIndicator(
                  key: const ValueKey('update.progress'),
                  value: value,
                ),
                Text('Téléchargement : ${(value * 100).round()} %'),
              ],
            ),
          ),
          actions: [
            // Une connexion lente mais vivante ne bloque jamais l'app.
            TextButton(
              key: const ValueKey('update.cancel'),
              onPressed: updater.cancel,
              child: const Text('Annuler'),
            ),
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
      SnackBar(content: Text(cancelled ? 'Mise à jour annulée.' : _impossible)),
    );
  }
}

/// « Place insuffisante » : `true` pour « Continuer quand même ». Fermer la
/// fenêtre vaut « Annuler ». Le focus va sur « Annuler » : le même appui sur
/// OK qui a choisi « Mettre à jour » ne relance pas une installation vouée
/// à l'échec sans que l'avertissement ait été lu.
Future<bool> confirmSpace(BuildContext context, ShortOfSpace short) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Place insuffisante'),
        content: Text(
          '${formatSize(short.free)} libres, environ '
          '${formatSize(short.needed)} nécessaires. Libérez de la place '
          '(par exemple le cache d\'autres applis).',
        ),
        actions: [
          TextButton(
            key: const ValueKey('update.spaceContinue'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuer quand même'),
          ),
          FilledButton(
            key: const ValueKey('update.spaceCancel'),
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
        ],
      ),
    ) ??
    false;

/// Au démarrage, une mise à jour en attente que la place retient
/// ([Updater.startup]) : « Continuer quand même » ouvre l'installateur,
/// « Annuler » la laisse pour le démarrage suivant.
Future<void> showHeldUpdateDialog(
  BuildContext context,
  Updater updater,
  ShortOfSpace short,
) async {
  if (!await confirmSpace(context, short) || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await updater.installer.installNow();
  } on Object catch (e) {
    // Appareil sans installateur : l'app continue, l'utilisateur le sait.
    log('Mise à jour en attente', error: e.runtimeType);
    messenger.showSnackBar(const SnackBar(content: Text(_impossible)));
  }
}

/// Tout échec de la mise à jour, signature refusée comprise.
const _impossible = "Mise à jour impossible pour l'instant.";

Future<void> _showPageDialog(
  BuildContext context,
  Future<void> Function(Uri page) openPage,
  Update update,
) async {
  final page = update.page;
  final open = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Version ${update.version} disponible'),
      content: update.notes.isEmpty
          ? null
          : SingleChildScrollView(
              child: Text(update.notes, key: const ValueKey('update.notes')),
            ),
      actions: [
        TextButton(
          key: const ValueKey('update.later'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Plus tard'),
        ),
        if (page != null)
          FilledButton(
            key: const ValueKey('update.openPage'),
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ouvrir la page'),
          ),
      ],
    ),
  );
  if (open != true || page == null) return;
  try {
    await openPage(page);
  } on Exception catch (e) {
    // Sans xdg-open, l'app continue : la release reste sur GitHub.
    log('Ouverture de la page de mise à jour', error: e.runtimeType);
  }
}
