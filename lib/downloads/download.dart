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

  /// Voir [posterNameOf].
  String get posterName => posterNameOf(item);

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

/// Nom de l'affiche dans le dossier des vidéos, tiré de la clé et jamais de
/// l'URL : celle du film (`poster-movie-12`), ou celle de la série pour un
/// épisode (`poster-series-34`), partagée par ses épisodes. Un id de série
/// qui ne tient pas dans un nom donne une affiche par épisode
/// (`poster-episode-56`). Sans extension : l'image est reconnue à son
/// contenu. Le préfixe la tient à l'écart des noms de vidéos.
String posterNameOf(PlayItem item) {
  final series = item.seriesId;
  if (series == null) return 'poster-movie-${item.id}';
  return _safeId.hasMatch(series)
      ? 'poster-series-$series'
      : 'poster-episode-${item.id}';
}

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

  File posterOf(Download download) =>
      File('${videos.path}${Platform.pathSeparator}${download.posterName}');

  /// Écrit l'affiche de [download] : dans un fichier à part, renommé une
  /// fois complet (jamais une image à moitié écrite à l'écran).
  Future<void> writePoster(Download download, List<int> bytes) async {
    final poster = posterOf(download);
    final part = File('${poster.path}.part');
    await videos.create(recursive: true);
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(poster.path);
  }

  /// Efface l'affiche de [download], si elle existe.
  Future<void> deletePoster(Download download) async {
    try {
      final poster = posterOf(download);
      if (await poster.exists()) await poster.delete();
    } on FileSystemException catch (e) {
      log('Affiche non effacée', error: e.osError?.errorCode);
    }
  }

  /// Le manifeste n'a pas pu être lu : ni rangement ([tidy]), qui
  /// effacerait des vidéos encore listées, ni écriture, qui l'écraserait
  /// (verrou passager, accès refusé), jusqu'au prochain chargement.
  var unreadable = false;

  /// Lit le manifeste, dans l'ordre d'ajout. Une entrée illisible est
  /// ignorée seule ; un fichier illisible donne une liste vide (voir
  /// [unreadable]) ; un fichier corrompu est mis de côté en
  /// `downloads.json.bak`. Une entrée prête dont le fichier a disparu est
  /// retirée ; une entrée en cours repasse en attente.
  Map<String, Download> load() {
    if (_unwritten[manifest.path] case final pending?) {
      return {
        for (final MapEntry(:key, :value) in pending.entries)
          key: value.status == DownloadStatus.running
              ? value.copyWith(status: DownloadStatus.queued)
              : value,
      };
    }
    Object? json;
    try {
      // Lecture synchrone : quelques Ko, lus au changement de compte.
      json = jsonDecode(manifest.readAsStringSync());
    } on PathNotFoundException {
      return const {};
    } on FileSystemException catch (e) {
      unreadable = true;
      log('Téléchargements non lus, liste vide', error: e.osError?.errorCode);
      return const {};
    } on FormatException {
      unreadable = true;
      log('Téléchargements illisibles, mis de côté en downloads.json.bak');
      try {
        manifest.renameSync('${manifest.path}.bak');
        // Mis de côté : on peut écrire de nouveau, sans ranger les vidéos,
        // que la copie liste peut-être.
        unreadable = false;
        _noTidy = true;
      } on FileSystemException catch (e) {
        log('Téléchargements non mis de côté', error: e.osError?.errorCode);
      }
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

  /// Manifeste mis de côté : les vidéos restent pour cette session.
  var _noTidy = false;

  Future<void> save(Map<String, Download> entries) {
    if (unreadable) return Future.value();
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
    if (unreadable || _noTidy) return;
    final kept = {
      for (final d in entries) ...[d.fileName, d.partName, d.posterName],
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
