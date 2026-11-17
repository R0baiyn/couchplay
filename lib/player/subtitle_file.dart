import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';

import '../logging.dart';

/// Extensions proposées par le sélecteur de sous-titres, `null` pour tous les
/// fichiers : sous Android, le filtre par extension grise souvent les bons
/// fichiers (types MIME inconnus).
List<String>? subtitleExtensions({required bool android}) =>
    android ? null : const ['srt', 'ass', 'ssa', 'vtt', 'sub'];

/// Texte d'un fichier de sous-titres : UTF-8, sinon Windows-1252 (beaucoup de
/// vieux .srt français).
String decodeSubtitleText(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// Ajoute à la lecture en cours les sous-titres d'un fichier choisi par
/// l'utilisateur (.srt, .ass, .vtt…). Le texte est passé à mpv plutôt que
/// le chemin : sous Android, le fichier choisi n'a pas toujours de chemin.
/// Un échec (sélecteur, lecture, mpv) est seulement journalisé.
Future<void> loadSubtitleFile(Player player) async {
  try {
    final extensions = subtitleExtensions(android: Platform.isAndroid);
    final file = (await FilePicker.pickFiles(
      dialogTitle: 'Fichier de sous-titres',
      type: extensions == null ? FileType.any : FileType.custom,
      allowedExtensions: extensions,
    )).firstOrNull;
    if (file == null) return;
    final text = decodeSubtitleText(await file.xFile.readAsBytes());
    await player.setSubtitleTrack(SubtitleTrack.data(text, title: file.name));
  } on Exception catch (e) {
    log('Sous-titres non chargés', error: e.runtimeType);
  }
}
