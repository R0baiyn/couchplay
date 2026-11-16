import 'dart:convert';
import 'dart:io';

import '../accounts/account_files.dart';
import '../library/library.dart';
import '../logging.dart';
import '../server/json_read.dart';

/// Où en est un téléchargement.
enum DownloadStatus {
  /// Dans la file, pas encore commencé ou interrompu (reprendra où il en
  /// était).
  queued,

  /// En cours : un seul à la fois.
  running,

  /// Mis en pause à la main : la file passe au suivant.
  paused,

  /// Fichier complet sur le disque.
  ready,

  /// Arrêté sur une erreur ([Download.error]) ; relançable.
  failed,
}

/// Un film ou un épisode téléchargé ou à télécharger : une entrée de
/// `downloads.json`. Jamais d'URL ni d'identifiant : de quoi l'afficher et
/// retrouver son fichier.
final class Download {
  const Download({
    required this.item,
    this.size = 0,
    this.received = 0,
    this.status = DownloadStatus.queued,
    this.error,
    required this.addedAt,
  });

  final PlayItem item;

  /// Taille du fichier en octets, 0 tant qu'elle est inconnue (connue à la
  /// première réponse du serveur).
  final int size;

  /// Octets reçus à la dernière écriture du manifeste. L'avancement en
  /// direct est dans `downloadProgressProvider`.
  final int received;
  final DownloadStatus status;

  /// Raison de l'échec, prête à afficher ([DownloadStatus.failed]).
  final String? error;
  final DateTime addedAt;

  String get key => item.key;

  /// Nom du fichier dans le dossier des vidéos du compte : `movie-12.mkv`,
  /// `episode-34.mp4`. Le type évite qu'un film et un épisode de même id
  /// se partagent un fichier.
  String get fileName => fileNameOf(item);

  /// Nom du fichier en cours de téléchargement.
  String get partName => '$fileName.part';

  /// Part reçue, entre 0 et 1, `null` si la taille est inconnue.
  double? get fraction =>
      size > 0 ? (received / size).clamp(0, 1).toDouble() : null;

  Download copyWith({
    int? size,
    int? received,
    DownloadStatus? status,
    String? error,
  }) => Download(
    item: item,
    size: size ?? this.size,
    received: received ?? this.received,
    status: status ?? this.status,
    // L'erreur ne survit pas à un changement d'état.
    error: error ?? (status == null ? this.error : null),
    addedAt: addedAt,
  );

  static Download? fromJson(String key, Object? json) {
    final map = asMap(json);
    final item = PlayItem.fromJson(key, map);
    if (item == null || !isDownloadable(item)) return null;
    final status = DownloadStatus.values.asNameMap()[asString(map['status'])];
    if (status == null) return null;
    return Download(
      item: item,
      size: asInt(map['size']) ?? 0,
      received: asInt(map['received']) ?? 0,
      // Un téléchargement en cours à la fermeture de l'app reprendra.
      status: status == DownloadStatus.running ? DownloadStatus.queued : status,
      error: asString(map['error']),
      addedAt:
          asDate(map['addedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, Object?> toJson() => {
    ...item.toJson(),
    'size': size,
    'received': received,
    'status': status.name,
    'error': ?error,
    'addedAt': addedAt.toUtc().toIso8601String(),
  };
}

/// L'id et l'extension viennent du serveur et finissent dans un nom de
/// fichier : lettres, chiffres, `_` et `-` seulement.
bool isDownloadable(PlayItem item) =>
    _safeId.hasMatch(item.id) && _safeExtension.hasMatch(item.extension);

final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final _safeExtension = RegExp(r'^[A-Za-z0-9]{1,10}$');

/// Voir [Download.fileName].
String fileNameOf(PlayItem item) =>
    '${item.isEpisode ? 'episode' : 'movie'}-${item.id}.${item.extension}';

/// Lecture et écriture de `accounts/<id>/downloads.json`, et des fichiers
/// du dossier des vidéos du compte ([videos]).
final class DownloadsStore {
  DownloadsStore(this.manifest, this.videos);

  final File manifest;
  final Directory videos;

  static const version = 1;

  File fileOf(Download download) =>
      File('${videos.path}${Platform.pathSeparator}${download.fileName}');

  File partOf(Download download) =>
      File('${videos.path}${Platform.pathSeparator}${download.partName}');

  /// Lit le manifeste, dans l'ordre d'ajout. Une entrée illisible est
  /// ignorée seule ; un fichier illisible donne une liste vide. Une entrée
  /// prête dont le fichier a disparu est retirée.
  Map<String, Download> load() {
    if (_unwritten[manifest.path] case final pending?) return pending;
    Object? json;
    try {
      // Lecture synchrone : quelques Ko, lus au changement de compte.
      json = jsonDecode(manifest.readAsStringSync());
    } on PathNotFoundException {
      return const {};
    } on Exception catch (e) {
      log('Téléchargements illisibles, liste vide', error: e.runtimeType);
      return const {};
    }
    final entries = <String, Download>{};
    for (final MapEntry(:key, :value) in asMap(
      asMap(json)['downloads'],
    ).entries) {
      final download = Download.fromJson(key, value);
      if (download == null) continue;
      if (download.status == DownloadStatus.ready &&
          !fileOf(download).existsSync()) {
        log('Téléchargement retiré : fichier disparu');
        continue;
      }
      entries[key] = download;
    }
    return entries;
  }

  /// Une seule file par fichier, comme pour `library.json` : le magasin est
  /// recréé à chaque changement de compte.
  static final _writers = <String, SerialFileWriter>{};

  /// Dernière liste confiée à la file et pas encore écrite : [load] la rend.
  static final _unwritten = <String, Map<String, Download>>{};

  Future<void> save(Map<String, Download> entries) {
    final path = manifest.path;
    _unwritten[path] = entries;
    final writer = _writers.putIfAbsent(
      path,
      () => SerialFileWriter(failure: 'Téléchargements non écrits'),
    );
    final json = {
      'version': version,
      'downloads': {
        for (final MapEntry(:key, :value) in entries.entries)
          key: value.toJson(),
      },
    };
    return writer
        .write(manifest, const JsonEncoder.withIndent(' ').convert(json))
        .whenComplete(() {
          if (identical(_unwritten[path], entries)) _unwritten.remove(path);
        });
  }

  /// Efface le fichier et le fichier partiel de [download], s'ils existent.
  Future<void> deleteFiles(Download download) async {
    for (final file in [fileOf(download), partOf(download)]) {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException catch (e) {
        log('Vidéo non effacée', error: e.osError?.errorCode);
      }
    }
  }

  /// Efface les fichiers du dossier des vidéos qu'aucune entrée ne
  /// réclame : restes d'une annulation interrompue, d'un manifeste perdu.
  Future<void> tidy(Iterable<Download> entries) async {
    final kept = {
      for (final d in entries) ...[d.fileName, d.partName],
    };
    try {
      if (!await videos.exists()) return;
      await for (final entry in videos.list()) {
        final name = entry.uri.pathSegments.last;
        if (entry is File && !kept.contains(name)) await entry.delete();
      }
    } on FileSystemException catch (e) {
      log('Vidéos orphelines non effacées', error: e.osError?.errorCode);
    }
  }
}
