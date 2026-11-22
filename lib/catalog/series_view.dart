import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../downloads/download.dart';
import '../downloads/downloads.dart';
import '../library/library.dart';
import '../television.dart';

/// « Télécharger la saison » : met en file, dans l'ordre, les épisodes de la
/// saison affichée qui ne sont ni téléchargés ni déjà en file (ceux en échec
/// repartent).
class SeasonDownloadButton extends ConsumerWidget {
  const SeasonDownloadButton({super.key, required this.items});

  final List<PlayItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty || ref.watch(televisionProvider)) {
      return const SizedBox.shrink();
    }
    // Deux chiffres seulement : l'avancement ne reconstruit pas le bouton.
    final (missing, ready) = ref.watch(
      downloadsProvider.select((s) {
        var missing = 0;
        var ready = 0;
        for (final item in items) {
          final status = s.entries[item.key]?.status;
          if (status == null || status == DownloadStatus.failed) missing++;
          if (status == DownloadStatus.ready) ready++;
        }
        return (missing, ready);
      }),
    );
    return OutlinedButton.icon(
      icon: Icon(
        missing > 0
            ? Icons.download_outlined
            : ready == items.length
            ? Icons.download_done
            : Icons.schedule,
      ),
      label: Text(
        missing > 0
            ? 'Télécharger la saison'
            : ready == items.length
            ? 'Saison téléchargée'
            : 'Saison en file',
      ),
      onPressed: missing > 0
          ? () => ref.read(downloadsProvider.notifier).add(items)
          : null,
    );
  }
}
