import 'download.dart';

/// Ce que la page « Téléchargements » affiche, calculé à partir des entrées :
/// fonctions pures, sans widget.

/// Tout ce qui n'est pas prêt : en cours, en attente, en pause, en échec.
List<Download> activeDownloads(Iterable<Download> entries) => [
  for (final d in entries)
    if (d.status != DownloadStatus.ready) d,
];

/// Les vidéos prêtes : un film seul, ou les épisodes d'une même série
/// ensemble, dans l'ordre d'ajout du premier.
Map<String, List<Download>> readyGroups(Iterable<Download> entries) {
  final groups = <String, List<Download>>{};
  for (final d in entries) {
    if (d.status == DownloadStatus.ready) {
      (groups[d.item.seriesId ?? d.key] ??= []).add(d);
    }
  }
  return groups;
}

/// Place prise : les vidéos prêtes, et ce qui est déjà reçu des autres.
int usedBytes(Iterable<Download> entries) => entries.fold(
  0,
  (sum, d) => sum + (d.status == DownloadStatus.ready ? d.size : d.received),
);

/// Le téléchargement en cours parmi [active], s'il y en a un.
Download? runningDownload(Iterable<Download> active) =>
    active.where((d) => d.status == DownloadStatus.running).firstOrNull;

/// Vrai si un téléchargement est en cours ou en file d'attente.
bool hasWaitingDownload(Iterable<Download> active) => active.any(
  (d) =>
      d.status == DownloadStatus.queued || d.status == DownloadStatus.running,
);

/// Place prise avec l'avancement en direct [live] du téléchargement
/// [running] : [stored] (qui compte déjà `running.received`) corrigé de la
/// différence.
int usedBytesLive(int stored, Download running, int live) =>
    stored + (live - running.received).clamp(0, live);

/// Les épisodes d'une série dans l'ordre (saison, numéro).
List<Download> sortedEpisodes(List<Download> episodes) =>
    [...episodes]..sort((a, b) {
      final season = a.item.season!.compareTo(b.item.season!);
      return season != 0 ? season : a.item.episode!.compareTo(b.item.episode!);
    });

/// Taille totale des fichiers de [downloads].
int totalSize(Iterable<Download> downloads) =>
    downloads.fold(0, (sum, d) => sum + d.size);

/// Part reçue, entre 0 et 1, `null` si la taille est inconnue.
double? receivedFraction(int received, int size) =>
    size > 0 ? (received / size).clamp(0, 1).toDouble() : null;
