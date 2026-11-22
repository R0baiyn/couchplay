import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../confirm.dart';
import '../library/library.dart';
import '../television.dart';
import 'download.dart';
import 'downloads.dart';

/// Part reçue de [download] : en direct pour celui qui tourne (seul ce qui
/// l'affiche se reconstruit), celle du manifeste sinon.
double? watchFraction(WidgetRef ref, Download download) {
  if (download.status != DownloadStatus.running) return download.fraction;
  return ref.watch(
        downloadProgressProvider.select(
          (p) => p?.key == download.key ? p!.fraction : null,
        ),
      ) ??
      download.fraction;
}

/// `34 %`.
String percent(double? fraction) =>
    fraction == null ? '' : '${(fraction * 100).floor()} %';

/// Supprime une vidéo prête après confirmation.
Future<void> confirmDelete(
  BuildContext context,
  WidgetRef ref,
  Download download,
) async {
  final delete = await confirm(
    context,
    title: 'Supprimer la vidéo ?',
    content:
        '« ${download.item.title} » sera effacée de cet appareil. '
        'Tu pourras la télécharger de nouveau.',
    action: 'Supprimer',
    focusCancel: true,
  );
  if (delete) await ref.read(downloadsProvider.notifier).remove(download.key);
}

/// État du téléchargement de [item] et l'appui qui va avec, partagés par
/// [DownloadButton] et l'entrée « Télécharger » du menu d'un épisode
/// (téléphone) : en attente, avancement, « Téléchargé », échec. Appui
/// pendant le téléchargement : pause, puis reprise ; sur « Téléchargé » :
/// suppression après confirmation ; sur un échec : nouvel essai. [item]
/// `null` : fichier inconnu, rien à appuyer.
({
  DownloadStatus? status,
  Widget icon,
  String label,
  String? note,
  VoidCallback? onPressed,
})
watchDownloadAction(BuildContext context, WidgetRef ref, PlayItem? item) {
  final download = item == null
      ? null
      : ref.watch(downloadsProvider.select((s) => s.entries[item.key]));
  final notifier = ref.read(downloadsProvider.notifier);
  final fraction = download == null ? null : watchFraction(ref, download);
  final theme = Theme.of(context);
  final status = download?.status;
  final (icon, label, note, onPressed) = switch (status) {
    null => (
      const Icon(Icons.download_outlined),
      'Télécharger',
      null,
      item == null ? null : () => notifier.add([item]),
    ),
    DownloadStatus.queued => (
      const Icon(Icons.schedule),
      'En attente',
      'Appuie pour mettre en pause',
      () => notifier.pause(download!.key),
    ),
    DownloadStatus.running => (
      SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(value: fraction, strokeWidth: 3),
      ),
      fraction == null ? 'Téléchargement' : percent(fraction),
      'Appuie pour mettre en pause',
      () => notifier.pause(download!.key),
    ),
    DownloadStatus.paused => (
      const Icon(Icons.play_arrow),
      'En pause${fraction == null ? '' : ' · ${percent(fraction)}'}',
      'Appuie pour reprendre',
      () => notifier.resume(download!.key),
    ),
    DownloadStatus.ready => (
      Icon(Icons.download_done, color: theme.colorScheme.primary),
      'Téléchargé',
      'Appuie pour supprimer la vidéo',
      () => confirmDelete(context, ref, download!),
    ),
    DownloadStatus.failed => (
      Icon(Icons.error_outline, color: theme.colorScheme.error),
      'Réessayer',
      download!.error,
      () => notifier.resume(download.key),
    ),
  };
  return (
    status: status,
    icon: icon,
    label: label,
    note: note,
    onPressed: onPressed,
  );
}

/// Bouton « Télécharger » d'un film ou d'un épisode, et son état
/// ([watchDownloadAction]).
///
/// Rien sur Android TV (D-034). [item] `null` : fichier inconnu, bouton
/// désactivé. [compact] : une icône (ligne d'épisode), sinon un bouton
/// avec son libellé.
class DownloadButton extends ConsumerWidget {
  const DownloadButton({super.key, required this.item, this.compact = false});

  final PlayItem? item;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(televisionProvider)) return const SizedBox.shrink();
    final (:status, :icon, :label, :note, :onPressed) = watchDownloadAction(
      context,
      ref,
      item,
    );
    final theme = Theme.of(context);

    if (compact) {
      return IconButton(
        tooltip: note == null ? label : '$label. $note',
        icon: icon,
        onPressed: onPressed,
      );
    }
    final button = OutlinedButton.icon(
      icon: icon,
      label: Text(label),
      onPressed: onPressed,
    );
    // L'échec dit pourquoi, sous le bouton.
    if (status != DownloadStatus.failed || note == null) return button;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        button,
        Text(
          note,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],
    );
  }
}
