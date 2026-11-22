import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'subtitle_file.dart';
import 'tech_info.dart';

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
              if (isRealTrack(t.id)) t,
          ];
          final subtitles = [
            for (final t in tracks.data?.subtitle ?? const <SubtitleTrack>[])
              if (isRealTrack(t.id)) t,
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
                key: const ValueKey('player.audioMenu'),
                tooltip: 'Audio',
                icon: const Icon(Icons.audiotrack),
                enabled: audio.length > 1,
                onOpened: onOpened,
                onSelected: player.setAudioTrack,
                itemBuilder: (_) => [
                  for (final (index, track) in audio.indexed)
                    PopupMenuItem(
                      key: ValueKey('player.audioTrack.${track.id}'),
                      value: track,
                      child: _Choice(
                        checked: track.id == selectedAudio,
                        label: trackLabel(
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
                key: const ValueKey('player.subtitleMenu'),
                tooltip: 'Sous-titres',
                icon: const Icon(Icons.subtitles),
                onOpened: onOpened,
                onSelected: player.setSubtitleTrack,
                itemBuilder: (_) => [
                  PopupMenuItem(
                    key: const ValueKey('player.subtitleFile'),
                    onTap: () => unawaited(loadSubtitleFile(player)),
                    child: const Row(
                      spacing: _gap,
                      children: [
                        Icon(Icons.upload_file),
                        Flexible(child: Text('Charger un fichier…')),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    key: const ValueKey('player.subtitleOff'),
                    value: SubtitleTrack.no(),
                    child: _Choice(checked: subtitlesOff, label: 'Désactivés'),
                  ),
                  for (final (index, track) in subtitles.indexed)
                    PopupMenuItem(
                      key: ValueKey('player.subtitleTrack.${track.id}'),
                      value: track,
                      child: _Choice(
                        checked: !subtitlesOff && track.id == selectedSubtitle,
                        label: trackLabel(
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

/// Écart entre l'icône et le texte d'une entrée de menu.
const _gap = 16.0;

/// Entrée cochable d'un menu de pistes. Pas de `CheckedPopupMenuItem` ni de
/// `ListTile` : leur tuile intérieure prend le focus des flèches sur TV
/// (navigation directionnelle), et OK y était sans effet.
class _Choice extends StatelessWidget {
  const _Choice({required this.checked, required this.label});

  final bool checked;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: checked,
    child: Row(
      spacing: _gap,
      children: [
        // Place gardée sans coche : les libellés restent alignés.
        Icon(checked ? Icons.done : null),
        Flexible(child: Text(label)),
      ],
    ),
  );
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
