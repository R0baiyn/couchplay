import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../confirm.dart';
import '../format.dart';
import '../settings/settings_screen.dart';
import 'download.dart';
import 'downloads.dart';
import 'downloads_active_view.dart';
import 'downloads_ready_view.dart';
import 'export.dart';
import 'offline_list.dart';

/// Onglet « Téléchargements » : ce qui est en cours ou en attente, puis les
/// vidéos prêtes (une vidéo prête se lit sans réseau).
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  /// Largeur de la liste sur grand écran.
  static const _maxWidth = 760.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(downloadsProvider.select((s) => s.entries));
    final holds = ref.watch(downloadHoldsProvider);
    final theme = Theme.of(context);

    final active = activeDownloads(entries.values);
    final groups = readyGroups(entries.values);
    final used = usedBytes(entries.values);
    final running = runningDownload(active);
    final waiting = hasWaitingDownload(active);
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
          // PC seulement : la vidéo est un fichier que l'on peut aller voir.
          if (ref.watch(desktopFilesProvider))
            IconButton(
              key: const ValueKey('downloads.openFolder'),
              tooltip: 'Ouvrir le dossier des vidéos',
              icon: const Icon(Icons.folder_open_outlined),
              onPressed: () => _openFolder(context, ref),
            ),
          if (entries.isNotEmpty)
            // Étroit : une icône, pour que le titre tienne en entier.
            if (MediaQuery.sizeOf(context).width < railMinWidth)
              IconButton(
                key: const ValueKey('downloads.removeAll'),
                tooltip: 'Tout supprimer',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () =>
                    _confirmRemoveAll(context, ref, entries.length),
              )
            else
              TextButton(
                key: const ValueKey('downloads.removeAll'),
                onPressed: () =>
                    _confirmRemoveAll(context, ref, entries.length),
                child: const Text('Tout supprimer'),
              ),
          const SettingsButton(),
        ],
      ),
      body: entries.isEmpty
          ? const _Empty()
          : LayoutBuilder(
              builder: (context, box) {
                final gutter = math.max(0.0, (box.maxWidth - _maxWidth) / 2);
                return ListView(
                  // Écran large : une colonne de lecture centrée, défilable sur
                  // toute la largeur.
                  padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _UsedSpace(stored: used, running: running),
                    ),
                    if (message != null)
                      Card(
                        key: const ValueKey('downloads.holdMessage'),
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: ListTile(
                          leading: const Icon(Icons.wifi_off),
                          title: Text(message),
                        ),
                      ),
                    if (active.isNotEmpty) ...[
                      header('En cours et en attente'),
                      for (final d in active)
                        ActiveRow(key: ValueKey(d.key), download: d),
                    ],
                    if (groups.isNotEmpty) ...[
                      header('Prêts'),
                      for (final group in groups.values)
                        if (group.first.item.isEpisode)
                          ReadySeries(
                            key: ValueKey(group.first.item.seriesId),
                            episodes: group,
                          )
                        else
                          ReadyMovie(
                            key: ValueKey(group.first.key),
                            download: group.first,
                          ),
                    ],
                  ],
                );
              },
            ),
    );
  }

  static Future<void> _openFolder(BuildContext context, WidgetRef ref) async {
    final folder = ref.read(downloadsProvider.notifier).folder;
    if (folder == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(openFolderProvider)(folder);
    } on IOException {
      messenger.showSnackBar(
        const SnackBar(content: Text("Impossible d'ouvrir le dossier.")),
      );
    }
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

/// Place prise. Le manifeste ne dit que ce qui était reçu à sa dernière
/// écriture : pour le téléchargement en cours, l'avancement en direct, que
/// seul ce texte suit.
class _UsedSpace extends ConsumerWidget {
  const _UsedSpace({required this.stored, required this.running});

  final int stored;
  final Download? running;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = this.running;
    final live = running == null
        ? null
        : ref.watch(
            downloadProgressProvider.select(
              (p) => p?.key == running.key ? p!.received : null,
            ),
          );
    final used = live == null ? stored : usedBytesLive(stored, running!, live);
    return Text(
      key: const ValueKey('downloads.usedSpace'),
      'Place occupée : ${formatSize(used)}',
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const ValueKey('downloads.empty'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              Icon(
                Icons.download_outlined,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              Text('Aucun téléchargement', style: theme.textTheme.titleMedium),
              const Text(
                'Sur la fiche d\'un film, appuie sur « Télécharger » ; sur '
                'celle d\'une série, sur « Télécharger la saison » ou sur '
                'l\'icône de téléchargement d\'un épisode. Les vidéos '
                'téléchargées se regardent ici, même sans réseau.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
