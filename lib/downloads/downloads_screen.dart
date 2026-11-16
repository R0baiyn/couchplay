import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/poster_grid.dart';
import '../confirm.dart';
import '../focus_ring.dart';
import '../format.dart';
import '../library/library.dart';
import '../library/library_store.dart';
import '../player/player_screen.dart';
import '../settings/settings_screen.dart';
import 'download.dart';
import 'download_button.dart';
import 'downloads.dart';
import 'export.dart';

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
    final running = active
        .where((d) => d.status == DownloadStatus.running)
        .firstOrNull;
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
          // PC seulement : la vidéo est un fichier que l'on peut aller voir.
          if (ref.watch(desktopFilesProvider))
            IconButton(
              tooltip: 'Ouvrir le dossier des vidéos',
              icon: const Icon(Icons.folder_open_outlined),
              onPressed: () => _openFolder(context, ref),
            ),
          if (entries.isNotEmpty)
            // Étroit : une icône, pour que le titre tienne en entier.
            if (MediaQuery.sizeOf(context).width < railMinWidth)
              IconButton(
                tooltip: 'Tout supprimer',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () =>
                    _confirmRemoveAll(context, ref, entries.length),
              )
            else
              TextButton(
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
                        if (group.first.item.isEpisode)
                          _ReadySeries(
                            key: ValueKey(group.first.item.seriesId),
                            episodes: group,
                          )
                        else
                          _ReadyMovie(
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
    final used = live == null
        ? stored
        : stored + (live - running!.received).clamp(0, live);
    return Text(
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

/// Vignette 2:3 d'un contenu téléchargé : l'affiche enregistrée à côté de
/// la vidéo (la page s'ouvre hors ligne), sinon celle du serveur, sinon
/// l'icône. Pour un épisode, l'affiche de sa série.
class _Poster extends ConsumerWidget {
  const _Poster(this.item, {this.width = 48});

  final PlayItem item;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Relue à chaque nouvelle liste : l'affiche arrive après la ligne.
    ref.watch(downloadsProvider.select((s) => s.entries));
    final file = ref.read(downloadsProvider.notifier).posterOf(item);
    final network = PosterImage(
      url: item.poster,
      icon: item.isEpisode ? Icons.tv : Icons.movie,
    );
    final image = file == null
        ? network
        : Image.file(
            file,
            fit: BoxFit.cover,
            cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).ceil(),
            // Fichier abîmé : le serveur, puis l'icône.
            errorBuilder: (_, _, _) => network,
          );
    return SizedBox(
      width: width,
      height: width * 3 / 2,
      child: ClipRRect(borderRadius: BorderRadius.circular(4), child: image),
    );
  }
}

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
  return size > 0 ? (received / size).clamp(0, 1).toDouble() : null;
}

/// Un téléchargement en cours, en attente, en pause ou en échec. Seuls
/// [_ActiveStatus] et [_ActiveBar] suivent l'avancement : la vignette et le
/// titre ne se reconstruisent pas plusieurs fois par seconde.
class _ActiveRow extends ConsumerWidget {
  const _ActiveRow({super.key, required this.download});

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
                      _Poster(d.item, width: 40),
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

/// Un film prêt, seul dans sa carte.
class _ReadyMovie extends StatelessWidget {
  const _ReadyMovie({super.key, required this.download});

  final Download download;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    clipBehavior: Clip.antiAlias,
    child: _ReadyRow(download: download),
  );
}

/// Une série : son affiche, son nom, le nombre d'épisodes et leur taille,
/// puis ses épisodes prêts dans l'ordre (saison, numéro).
class _ReadySeries extends StatelessWidget {
  const _ReadySeries({super.key, required this.episodes});

  final List<Download> episodes;

  @override
  Widget build(BuildContext context) {
    final sorted = [...episodes]
      ..sort((a, b) {
        final season = a.item.season!.compareTo(b.item.season!);
        return season != 0
            ? season
            : a.item.episode!.compareTo(b.item.episode!);
      });
    final first = sorted.first.item;
    final size = episodes.fold(0, (sum, d) => sum + d.size);
    final count = episodes.length;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              spacing: 12,
              children: [
                _Poster(first, width: 56),
                Expanded(
                  child: Text(
                    '${first.name} · $count '
                    '${count > 1 ? 'épisodes' : 'épisode'} · '
                    '${formatSize(size)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          for (final d in sorted) _ReadyRow(key: ValueKey(d.key), download: d),
        ],
      ),
    );
  }
}

/// Une vidéo prête : appui = lecture, ⤓ = export (PC), poubelle =
/// suppression. Un film a sa vignette ; un épisode est sous celle de sa
/// série. Où on en est : barre de visionnage, « Reprendre à … », coche si
/// vu (bibliothèque locale, sans serveur).
class _ReadyRow extends ConsumerStatefulWidget {
  const _ReadyRow({super.key, required this.download});

  final Download download;

  @override
  ConsumerState<_ReadyRow> createState() => _ReadyRowState();
}

class _ReadyRowState extends ConsumerState<_ReadyRow> {
  /// Copie en cours : l'action est désactivée.
  var _exporting = false;

  /// Copie la vidéo dans un dossier choisi, sous son vrai titre. Une vidéo
  /// effacée entre-temps (« Effacer une fois vu », suppression) est dite,
  /// pas avalée.
  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    final item = widget.download.item;
    // Grisé dès le choix du dossier : sous Linux, il ne bloque pas la
    // fenêtre, et un second appui lancerait un second export.
    setState(() => _exporting = true);
    try {
      final String? path;
      try {
        path = await ref.read(pickFolderProvider)();
      } on Exception {
        say("Impossible d'ouvrir le choix du dossier.");
        return;
      }
      if (path == null || !mounted) return;
      final source = ref.read(downloadsProvider.notifier).fileOf(item);
      if (source == null) {
        say("La vidéo n'existe plus.");
        return;
      }
      await exportVideo(source, Directory(path), exportFileName(item));
      say('Exporté dans $path');
    } on ExportException catch (e) {
      say(e.message);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final download = widget.download;
    final item = download.item;
    final episode = item.isEpisode;
    final theme = Theme.of(context);
    final progress = ref.watch(
      libraryProvider.select((l) => l.progress[item.key]),
    );
    // Où on en est, en texte et en coche seulement (D-046).
    final watched = progress?.watched ?? false;
    final resume = progress?.resumeAt;
    final subtitle = _exporting
        ? 'Export en cours · ${formatSize(download.size)}'
        : [
            formatSize(download.size),
            if (resume != null) 'Reprendre à ${formatTime(resume)}',
          ].join(' · ');
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => openPlayer(context, ref, item),
            child: FocusRing(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  spacing: 12,
                  children: [
                    if (!episode) _Poster(item),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 4,
                        children: [
                          Row(
                            spacing: 6,
                            children: [
                              if (watched)
                                Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  semanticLabel: 'Vu',
                                  color: theme.colorScheme.primary,
                                ),
                              Flexible(
                                child: Text(
                                  episode
                                      ? 'S${item.season}E${item.episode}'
                                            '${item.episodeTitle == null ? '' : ' · ${item.episodeTitle}'}'
                                      : item.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: episode
                                      ? theme.textTheme.bodyMedium
                                      : theme.textTheme.titleSmall,
                                ),
                              ),
                            ],
                          ),
                          Text(subtitle, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (ref.watch(desktopFilesProvider))
          IconButton(
            tooltip: 'Exporter la vidéo',
            icon: const Icon(Icons.save_alt),
            onPressed: _exporting ? null : _export,
          ),
        IconButton(
          tooltip: 'Supprimer la vidéo',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => confirmDelete(context, ref, download),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
