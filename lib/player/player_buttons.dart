import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'player_tracks.dart';

/// Rangée de boutons du bas des contrôles : lecture, ±10 s, volume, pistes,
/// remplissage, plein écran. Le focus de [playFocus] reste créé et libéré par
/// les contrôles, qui s'en servent aussi pour ↑ ↓ sur Android.
class PlayerButtons extends StatelessWidget {
  const PlayerButtons({
    super.key,
    required this.player,
    required this.playFocus,
    required this.fill,
    required this.fullscreen,
    required this.volume,
    required this.onActivity,
    required this.onRewind,
    required this.onForward,
    required this.onToggleFill,
    required this.onToggleFullscreen,
  });

  final Player player;
  final FocusNode playFocus;
  final bool fill;

  /// `null` : pas de bouton plein écran.
  final bool? fullscreen;
  final bool volume;

  /// Un bouton a servi : les contrôles restent affichés.
  final VoidCallback onActivity;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final VoidCallback onToggleFill;
  final VoidCallback onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    final fullscreen = this.fullscreen;
    return FocusTraversalGroup(
      child: Row(
        children: [
          StreamBuilder<bool>(
            stream: player.stream.playing,
            initialData: player.state.playing,
            builder: (context, snapshot) {
              final playing = snapshot.data ?? false;
              return IconButton(
                key: const ValueKey('player.playPause'),
                focusNode: playFocus,
                tooltip: playing ? 'Pause' : 'Lecture',
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                onPressed: () {
                  player.playOrPause();
                  onActivity();
                },
              );
            },
          ),
          IconButton(
            key: const ValueKey('player.rewind'),
            tooltip: 'Reculer de 10 s',
            icon: const Icon(Icons.replay_10),
            onPressed: onRewind,
          ),
          IconButton(
            key: const ValueKey('player.forward'),
            tooltip: 'Avancer de 10 s',
            icon: const Icon(Icons.forward_10),
            onPressed: onForward,
          ),
          if (volume) _VolumeButton(player: player, onChanged: onActivity),
          const Spacer(),
          TracksMenu(player: player, onOpened: onActivity),
          IconButton(
            key: const ValueKey('player.fill'),
            tooltip: fill ? 'Image entière' : 'Remplir l\'écran',
            icon: Icon(fill ? Icons.fit_screen : Icons.crop_free),
            onPressed: () {
              onToggleFill();
              onActivity();
            },
          ),
          if (fullscreen != null)
            IconButton(
              key: const ValueKey('player.fullscreen'),
              tooltip: fullscreen ? 'Quitter le plein écran' : 'Plein écran',
              icon: Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
              onPressed: onToggleFullscreen,
            ),
        ],
      ),
    );
  }
}

class _VolumeButton extends StatefulWidget {
  const _VolumeButton({required this.player, required this.onChanged});

  final Player player;
  final VoidCallback onChanged;

  @override
  State<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<_VolumeButton> {
  // Volume rendu quand on remet le son.
  double _beforeMute = 100;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (context, snapshot) {
        final volume = snapshot.data ?? 100;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey('player.mute'),
              tooltip: volume == 0 ? 'Remettre le son' : 'Couper le son',
              icon: Icon(volume == 0 ? Icons.volume_off : Icons.volume_up),
              onPressed: () {
                if (volume > 0) _beforeMute = volume;
                player.setVolume(volume == 0 ? _beforeMute : 0);
                widget.onChanged();
              },
            ),
            SizedBox(
              width: 100,
              child: Slider(
                key: const ValueKey('player.volume'),
                value: volume.clamp(0, 100),
                max: 100,
                onChanged: (value) {
                  player.setVolume(value);
                  widget.onChanged();
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
