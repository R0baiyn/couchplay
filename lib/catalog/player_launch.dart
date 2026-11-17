import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../library/library.dart';
import '../library/library_store.dart';
import '../player/player_screen.dart';
import 'catalog_providers.dart';

/// Ouvre le lecteur sur un film ou un épisode du compte actif. Un contenu
/// commencé propose de reprendre ou de recommencer ; avec [resume], la
/// lecture reprend là sans rien demander (« Continuer à regarder »).
Future<void> openPlayer(
  BuildContext context,
  WidgetRef ref,
  PlayItem item, {
  Duration? resume,
}) async {
  // Un double clic sur « Lecture » ne doit pas empiler deux lecteurs.
  if (ModalRoute.of(context)?.isCurrent == false) return;
  var start = resume;
  if (start == null) {
    if (ref.read(libraryProvider).progress[item.key]?.resumeAt
        case final saved?) {
      start = await showDialog<Duration>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(item.title),
          actions: [
            TextButton(
              key: const ValueKey('player.resumeRestart'),
              onPressed: () => Navigator.pop(context, Duration.zero),
              child: const Text('Recommencer'),
            ),
            FilledButton(
              key: const ValueKey('player.resumeContinue'),
              autofocus: true,
              onPressed: () => Navigator.pop(context, saved),
              child: Text('Reprendre à ${formatTime(saved)}'),
            ),
          ],
        ),
      );
      // Fermé sans choisir : on reste sur la fiche.
      if (start == null || !context.mounted) return;
    }
  }
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        item: item,
        seriesDetails: seriesDetailsProvider.call,
        startAt: start,
      ),
    ),
  );
}
