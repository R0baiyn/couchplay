import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library.dart';

/// Choix du dossier d'export : son chemin, `null` si annulé. Surchargé dans
/// les tests.
final pickFolderProvider = Provider<Future<String?> Function()>(
  (ref) =>
      () =>
          FilePicker.getDirectoryPath(dialogTitle: 'Exporter dans le dossier'),
);

/// Nom du fichier d'une vidéo exportée : le vrai titre (le film, ou
/// `<série> S01E02 <titre>`) et l'extension de la vidéo. Le titre vient du
/// serveur : le résultat n'a jamais de séparateur de dossier, de `..`, de
/// caractère interdit sous Windows ni de nom réservé, et sa longueur est
/// bornée. Titre vide : le nom du fichier du disque (`movie-12`).
String exportFileName(PlayItem item) {
  String two(int n) => n.toString().padLeft(2, '0');
  final raw = item.isEpisode
      ? '${item.name} S${two(item.season!)}E${two(item.episode!)}'
            '${item.episodeTitle == null ? '' : ' ${item.episodeTitle}'}'
      : item.name;
  var stem = _clean(raw);
  if (stem.isEmpty) stem = '${item.isEpisode ? 'episode' : 'movie'}-${item.id}';
  if (_reserved.hasMatch(stem)) stem = '_$stem';
  return '$stem.${item.extension}';
}

/// Longueur maximale du nom sans extension : de la marge sous les 260
/// caractères d'un chemin Windows, dossier choisi compris.
const _maxStem = 120;

final _forbidden = RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]');
final _reserved = RegExp(
  r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$',
  caseSensitive: false,
);

String _clean(String raw) {
  final stem = raw
      .replaceAll(_forbidden, '_')
      .replaceAll(RegExp(r'\.{2,}'), '.')
      .replaceAll(RegExp(r'\s+'), ' ');
  // Par points de code : pas de paire de substitution coupée en deux.
  final cut = String.fromCharCodes(stem.runes.take(_maxStem));
  // Windows retire les points et espaces de fin ; un point au début ferait
  // un fichier caché, ou « .. ».
  return cut.replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
}

/// L'export a échoué : [message] est prêt à afficher.
final class ExportException implements Exception {
  const ExportException(this.message);

  final String message;

  @override
  String toString() => 'ExportException: $message';
}

/// Copie [source] dans [folder] sous [name], sans jamais écraser un fichier :
/// si le nom est pris, `Titre (2).mkv`, `Titre (3).mkv`… Rend le fichier
/// créé. La copie se fait dans un fichier `.part`, renommé à la fin : en cas
/// d'erreur (place, droits, vidéo disparue), aucun fichier partiel ne reste
/// et l'erreur est dite par une [ExportException].
Future<File> exportVideo(File source, Directory folder, String name) async {
  if (!await source.exists()) {
    throw const ExportException('La vidéo n\'existe plus.');
  }
  File? part;
  File? reserved;
  try {
    // Créé ici, exclusivement : jamais le `.part` d'un autre (un
    // téléchargement du navigateur, un autre export du même titre).
    part = await _createNew(
      (n) => '${folder.path}${Platform.pathSeparator}$name.$pid-$n.part',
    );
    await source.copy(part.path);
    // Choisi à la fin : un fichier apparu pendant la copie n'est pas écrasé.
    final dot = name.lastIndexOf('.');
    final stem = name.substring(0, dot);
    final extension = name.substring(dot);
    reserved = await _createNew(
      (n) =>
          '${folder.path}${Platform.pathSeparator}'
          '$stem${n == 1 ? '' : ' ($n)'}$extension',
    );
    return await part.rename(reserved.path);
  } on FileSystemException catch (e) {
    // Seulement les fichiers créés par cet export.
    for (final file in [?part, ?reserved]) {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Rien de plus à faire : le fichier reste, mais l'erreur d'origine
        // est celle que l'on dit.
      }
    }
    throw ExportException(_message(e.osError?.errorCode));
  }
}

/// Crée, vide et de façon exclusive, le premier chemin libre parmi
/// `path(1)`, `path(2)`… : un autre export qui fait de même au même moment
/// prend le suivant, et un fichier existant n'est jamais repris.
Future<File> _createNew(String Function(int n) path) async {
  for (var n = 1; ; n++) {
    final candidate = File(path(n));
    if (await candidate.exists()) continue;
    try {
      return await candidate.create(exclusive: true);
    } on FileSystemException {
      // Pris entre-temps : le suivant. Une autre erreur (dossier disparu)
      // est rendue telle quelle.
      if (!await candidate.exists()) rethrow;
    }
  }
}

/// Codes d'erreur système : Windows (5 accès refusé, 112 disque plein) et
/// POSIX (13 droits, 30 lecture seule, 28 plus de place, 2 et 3 : le dossier
/// choisi a disparu, la vidéo existait au début de la copie).
String _message(int? code) => switch (code) {
  28 || 112 => 'Pas assez de place dans ce dossier.',
  5 || 13 || 30 => 'Ce dossier n\'est pas accessible en écriture.',
  2 || 3 => 'Le dossier choisi ou la vidéo n\'existe plus.',
  _ => 'L\'export a échoué.',
};
