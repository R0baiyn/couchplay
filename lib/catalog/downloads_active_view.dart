import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../confirm.dart';
import '../format.dart';
import '../downloads/download.dart';
import '../downloads/download_button.dart';
import '../downloads/downloads.dart';
import 'downloads_poster.dart';
import '../downloads/offline_list.dart';

/// Octets reçus et taille totale (0 si inconnue) : en direct pour le
/// téléchargement en cours.
(int, int) _watchBytes(WidgetRef ref, Download d) {
  if (d.status != DownloadStatus.running) return (d.received, d.size);
  return ref.watch(
        downloadProgressProvider.select(
          (p) => p?.key == d.key ? (p!.received, p.size) : null,
        ),
      ) ??
      (d.received, d.size);
}

double? _fraction((int, int) bytes) {
  final (received, size) = bytes;
  return receivedFraction(received, size);
}

/// Un téléchargement en cours, en attente, en pause ou en échec. Seuls
/// [_ActiveStatus] et [_ActiveBar] suivent l'avancement : la vignette et le
/// titre ne se reconstruisent pas plusieurs fois par seconde.
class ActiveRow extends ConsumerWidget {
  const ActiveRow({super.key, required this.download});

  final Download download;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = download;
    final notifier = ref.read(downloadsProvider.notifier);
    final failed = d.status == DownloadStatus.failed;
    final stopped = d.status == DownloadStatus.paused || failed;
    // La ✕ et la pause à côté de la ligne et non en `trailing` : voir
    // l'historique (flèches de la télécommande).
    return Card(
      key: ValueKey('downloads.activeRow.${d.key}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    spacing: 12,
                    children: [
                      DownloadPoster(d.item, width: 40),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 4,
                          children: [
                            Text(
                              d.item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            _ActiveStatus(d),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('downloads.pauseResume.${d.key}'),
                tooltip: switch (d.status) {
                  DownloadStatus.failed => 'Réessayer',
                  DownloadStatus.paused => 'Reprendre',
                  _ => 'Mettre en pause',
                },
                icon: Icon(
                  failed
                      ? Icons.refresh
                      : stopped
                      ? Icons.play_arrow
                      : Icons.pause,
                ),
                onPressed: () =>
                    stopped ? notifier.resume(d.key) : notifier.pause(d.key),
              ),
              IconButton(
                key: ValueKey('downloads.cancel.${d.key}'),
                tooltip: 'Annuler',
                icon: const Icon(Icons.close),
                onPressed: () => _cancel(context, ref),
              ),
              const SizedBox(width: 4),
            ],
          ),
          // En pause avant d'avoir reçu quoi que ce soit : pas de barre
          // (indéterminée, elle s'animerait comme un transfert).
          if (d.status == DownloadStatus.running ||
              (d.status == DownloadStatus.paused && d.fraction != null))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _ActiveBar(d),
            ),
        ],
      ),
    );
  }

  /// Ce qui est déjà reçu est perdu : on le confirme.
  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    if (download.received > 0) {
      final cancel = await confirm(
        context,
        title: 'Annuler le téléchargement ?',
        content:
            '« ${download.item.title} » : ce qui est déjà reçu sera effacé.',
        action: 'Annuler le téléchargement',
        focusCancel: true,
      );
      if (!cancel) return;
    }
    await ref.read(downloadsProvider.notifier).remove(download.key);
  }
}

/// `34 % · 15 Mo / 46 Mo`, l'attente, la pause ou la raison d'un échec.
class _ActiveStatus extends ConsumerWidget {
  const _ActiveStatus(this.download);

  final Download download;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = download;
    final bytes = _watchBytes(ref, d);
    final (received, size) = bytes;
    final fraction = _fraction(bytes);
    final amount = fraction == null
        ? formatSize(received)
        : '${percent(fraction)} · ${formatSize(received)} / '
              '${formatSize(size)}';
    final theme = Theme.of(context);
    final failed = d.status == DownloadStatus.failed;
    return Text(
      switch (d.status) {
        DownloadStatus.queued =>
          size > 0 ? 'En attente · ${formatSize(size)}' : 'En attente',
        DownloadStatus.running => amount,
        DownloadStatus.paused =>
          received > 0 ? 'En pause · $amount' : 'En pause',
        DownloadStatus.failed => d.error ?? 'Échec du téléchargement',
        DownloadStatus.ready => '',
      },
      style: failed
          ? theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)
          : theme.textTheme.bodySmall,
    );
  }
}

/// Barre d'avancement sur toute la largeur de la ligne.
class _ActiveBar extends ConsumerWidget {
  const _ActiveBar(this.download);

  final Download download;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LinearProgressIndicator(
    value: _fraction(_watchBytes(ref, download)),
    minHeight: 6,
    borderRadius: BorderRadius.circular(3),
  );
}
