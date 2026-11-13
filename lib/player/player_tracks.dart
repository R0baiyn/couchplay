import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../logging.dart';

/// Ajoute à la lecture en cours les sous-titres d'un fichier choisi par
/// l'utilisateur (.srt, .ass, .vtt…). Le texte est passé à mpv plutôt que
/// le chemin : sous Android, le fichier choisi n'a pas toujours de chemin.
/// Un échec (sélecteur, lecture, mpv) est seulement journalisé.
Future<void> loadSubtitleFile(Player player) async {
  try {
    final file = (await FilePicker.pickFiles(
      dialogTitle: 'Fichier de sous-titres',
    )).firstOrNull;
    if (file == null) return;
    final bytes = await file.xFile.readAsBytes();
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      // Beaucoup de vieux .srt français sont en Windows-1252.
      text = latin1.decode(bytes);
    }
    await player.setSubtitleTrack(SubtitleTrack.data(text, title: file.name));
  } on Exception catch (e) {
    log('Sous-titres non chargés', error: e.runtimeType);
  }
}

/// Menus Audio et Sous-titres, d'après les pistes du fichier.
class TracksMenu extends StatelessWidget {
  const TracksMenu({super.key, required this.player, required this.onOpened});

  final Player player;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Track>(
      stream: player.stream.track,
      initialData: player.state.track,
      builder: (context, current) => StreamBuilder<Tracks>(
        stream: player.stream.tracks,
        initialData: player.state.tracks,
        builder: (context, tracks) {
          final audio = [
            for (final t in tracks.data?.audio ?? const <AudioTrack>[])
              if (t.id != 'auto' && t.id != 'no') t,
          ];
          final subtitles = [
            for (final t in tracks.data?.subtitle ?? const <SubtitleTrack>[])
              if (t.id != 'auto' && t.id != 'no') t,
          ];
          final selectedAudio = current.data?.audio.id;
          final selectedSubtitle = current.data?.subtitle.id;
          // À l'ouverture, media_kit dit « auto » : les sous-titres sont
          // alors désactivés (voir Playback), et l'audio suit la langue.
          final subtitlesOff =
              selectedSubtitle == null ||
              selectedSubtitle == 'no' ||
              selectedSubtitle == 'auto';
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<AudioTrack>(
                tooltip: 'Audio',
                icon: const Icon(Icons.audiotrack),
                enabled: audio.length > 1,
                onOpened: onOpened,
                onSelected: player.setAudioTrack,
                itemBuilder: (_) => [
                  for (final (index, track) in audio.indexed)
                    CheckedPopupMenuItem(
                      value: track,
                      checked: track.id == selectedAudio,
                      child: Text(
                        trackLabel(
                          index: index,
                          language: track.language,
                          title: track.title,
                          codec: track.codec,
                        ),
                      ),
                    ),
                ],
              ),
              PopupMenuButton<SubtitleTrack>(
                tooltip: 'Sous-titres',
                icon: const Icon(Icons.subtitles),
                onOpened: onOpened,
                onSelected: player.setSubtitleTrack,
                itemBuilder: (_) => [
                  PopupMenuItem(
                    onTap: () => unawaited(loadSubtitleFile(player)),
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.upload_file),
                      title: Text('Charger un fichier…'),
                    ),
                  ),
                  const PopupMenuDivider(),
                  CheckedPopupMenuItem(
                    value: SubtitleTrack.no(),
                    checked: subtitlesOff,
                    child: const Text('Désactivés'),
                  ),
                  for (final (index, track) in subtitles.indexed)
                    CheckedPopupMenuItem(
                      value: track,
                      checked: !subtitlesOff && track.id == selectedSubtitle,
                      child: Text(
                        trackLabel(
                          index: index,
                          language: track.language,
                          title: track.title,
                          codec: track.codec,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

const _languages = {
  'fr': 'Français',
  'fre': 'Français',
  'fra': 'Français',
  'en': 'Anglais',
  'eng': 'Anglais',
  'es': 'Espagnol',
  'spa': 'Espagnol',
  'it': 'Italien',
  'ita': 'Italien',
  'de': 'Allemand',
  'ger': 'Allemand',
  'deu': 'Allemand',
  'pt': 'Portugais',
  'por': 'Portugais',
  'ar': 'Arabe',
  'ara': 'Arabe',
  'ja': 'Japonais',
  'jpn': 'Japonais',
};

/// Libellé d'une piste : langue, titre et codec quand ils sont connus,
/// sinon « Piste n ».
String trackLabel({
  required int index,
  String? language,
  String? title,
  String? codec,
}) {
  final parts = <String>[
    if (language != null && language.isNotEmpty)
      _languages[language.toLowerCase()] ?? language,
    if (title != null && title.isNotEmpty && title != language) title,
  ];
  final label = parts.isEmpty ? 'Piste ${index + 1}' : parts.join(' · ');
  return codec == null || codec.isEmpty ? label : '$label ($codec)';
}
