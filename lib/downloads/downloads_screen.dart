import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../confirm.dart';
import '../focus_ring.dart';
import '../format.dart';
import '../player/player_screen.dart';
import '../settings/settings_screen.dart';
import 'download.dart';
import 'download_button.dart';
import 'downloads.dart';

/// Onglet « Téléchargements » : ce qui est en cours ou en attente, puis les
/// vidéos prêtes (une vidéo prête se lit sans réseau).
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(downloadsProvider.select((s) => s.entries));
    final holds = ref.watch(downloadHoldsProvider);
    final theme = Theme.of(context);

    final active = [
      for (final d in entries.values)
        if (d.status != DownloadStatus.ready) d,
    ];
    // Un film seul, ou les épisodes d'une même série ensemble, dans l'ordre
    // d'ajout du premier.
    final groups = <String, List<Download>>{};
    for (final d in entries.values) {
      if (d.status == DownloadStatus.ready) {
        (groups[d.item.seriesId ?? d.key] ??= []).add(d);
      }
    }
    // Place prise : les vidéos prêtes, et ce qui est déjà reçu des autres.
    final used = entries.values.fold(
      0,
      (sum, d) =>
          sum + (d.status == DownloadStatus.ready ? d.size : d.received),
    );
    final waiting = active.any(
      (d) =>
          d.status == DownloadStatus.queued ||
          d.status == DownloadStatus.running,
    );
    final message = !waiting
        ? null
        : holds.waitingForWifi
        ? 'En attente d\'un réseau Wi-Fi : les téléchargements reprendront '
              'dès qu\'il sera connecté.'
        : holds.reasons.contains(DownloadHold.playback)
        ? 'En pause pendant la lecture : reprise à la sortie du lecteur.'
        : null;

    Widget header(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: theme.textTheme.titleMedium),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Téléchargements'),
        actions: [
          if (entries.isNotEmpty)
            TextButton(
              onPressed: () => _confirmRemoveAll(context, ref, entries.length),
              child: const Text('Tout supprimer'),
            ),
          const SettingsButton(),
        ],
      ),
      body: entries.isEmpty
          ? const _Empty()
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    'Place occupée : ${formatSize(used)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (message != null)
                  Card(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: ListTile(
                      leading: const Icon(Icons.wifi_off),
                      title: Text(message),
                    ),
                  ),
                if (active.isNotEmpty) ...[
                  header('En cours et en attente'),
                  for (final d in active)
                    _ActiveRow(key: ValueKey(d.key), download: d),
                ],
                if (groups.isNotEmpty) ...[
                  header('Prêts'),
                  for (final group in groups.values)
                    ..._readyGroup(context, ref, group),
                ],
              ],
            ),
    );
  }

  static List<Widget> _readyGroup(
    BuildContext context,
    WidgetRef ref,
    List<Download> group,
  ) {
    final first = group.first.item;
    if (!first.isEpisode) {
      return [_ReadyRow(key: ValueKey(first.key), download: group.first)];
    }
    final episodes = [...group]
      ..sort((a, b) {
        final season = a.item.season!.compareTo(b.item.season!);
        return season != 0
            ? season
            : a.item.episode!.compareTo(b.item.episode!);
      });
    final size = group.fold(0, (sum, d) => sum + d.size);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          '${first.name} · ${group.length} '
          '${group.length > 1 ? 'épisodes' : 'épisode'} · ${formatSize(size)}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      for (final d in episodes) _ReadyRow(key: ValueKey(d.key), download: d),
    ];
  }

  static Future<void> _confirmRemoveAll(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) async {
    final all = await confirm(
      context,
      title: 'Tout supprimer ?',
      content:
          '$count ${count > 1 ? 'téléchargements seront effacés' : 'téléchargement sera effacé'} '
          'de cet appareil, y compris ceux en cours. Tu pourras les '
          'télécharger de nouveau.',
      action: 'Tout supprimer',
      focusCancel: true,
    );
    if (all) await ref.read(downloadsProvider.notifier).removeAll();
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Icon(Icons.download_outlined, size: 48),
          Text('Aucun téléchargement'),
          Text(
            'Le bouton « Télécharger » d\'un film ou d\'un épisode permet '
            'de le regarder sans réseau.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

/// Un téléchargement en cours, en attente, en pause ou en échec.
class _ActiveRow extends ConsumerWidget {
  const _ActiveRow({super.key, required this.download});

  final Download download;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = download;
    final notifier = ref.read(downloadsProvider.notifier);
    final fraction = watchFraction(ref, d);
    final text = switch (d.status) {
      DownloadStatus.queued => 'En attente',
      DownloadStatus.running =>
        fraction == null ? 'Téléchargement' : percent(fraction),
      DownloadStatus.paused =>
        'En pause${fraction == null ? '' : ' · ${percent(fraction)}'}',
      DownloadStatus.failed => d.error ?? 'Échec du téléchargement',
      DownloadStatus.ready => '',
    };
    final failed = d.status == DownloadStatus.failed;
    final stopped = d.status == DownloadStatus.paused || failed;
    // La ✕ et la pause à côté de la ligne et non en `trailing` : voir
    // l'historique (flèches de la télécommande).
    return Row(
      children: [
        Expanded(
          child: ListTile(
            title: Text(d.item.title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(
                  d.size > 0 && !failed
                      ? '$text · ${formatSize(d.size)}'
                      : text,
                  style: failed
                      ? TextStyle(color: Theme.of(context).colorScheme.error)
                      : null,
                ),
                if (!failed && d.status != DownloadStatus.queued)
                  LinearProgressIndicator(value: fraction),
              ],
            ),
          ),
        ),
        IconButton(
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
          tooltip: 'Annuler',
          icon: const Icon(Icons.close),
          onPressed: () => _cancel(context, ref),
        ),
        const SizedBox(width: 8),
      ],
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

/// Une vidéo prête : appui = lecture, ✕ = suppression.
class _ReadyRow extends ConsumerWidget {
  const _ReadyRow({super.key, required this.download});

  final Download download;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = download.item;
    final episode = item.isEpisode;
    return Row(
      children: [
        Expanded(
          child: ListTile(
            title: FocusRing(
              child: Text(
                episode
                    ? 'S${item.season}E${item.episode}'
                          '${item.episodeTitle == null ? '' : ' · ${item.episodeTitle}'}'
                    : item.name,
              ),
            ),
            subtitle: Text(formatSize(download.size)),
            onTap: () => openPlayer(context, ref, item),
          ),
        ),
        IconButton(
          tooltip: 'Supprimer la vidéo',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => confirmDelete(context, ref, download),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
