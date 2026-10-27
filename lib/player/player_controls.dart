import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

/// Contrôles du lecteur, par-dessus la vidéo.
///
/// - Souris : clic = pause, double-clic = plein écran ; les contrôles et le
///   curseur se masquent après 3 s sans mouvement.
/// - Toucher : un toucher affiche ou masque les contrôles, un double toucher
///   à gauche ou à droite recule ou avance de 10 s.
/// - Clavier : Espace (pause), ← → (±10 s), ↑ ↓ (volume), F (plein écran),
///   Échap (quitte le plein écran, puis le lecteur), Tab pour les boutons.
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.title,
    required this.fill,
    required this.onToggleFill,
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.onExit,
  });

  final Player player;
  final String title;

  /// `true` : l'image remplit l'écran, quitte à être rognée.
  final bool fill;
  final VoidCallback onToggleFill;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onExit;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  static const _hideAfter = Duration(seconds: 3);
  static const _step = Duration(seconds: 10);

  var _visible = true;
  Timer? _hideTimer;

  Player get _player => widget.player;

  @override
  void initState() {
    super.initState();
    _show();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  /// Affiche les contrôles et relance le compte à rebours.
  void _show() {
    _hideTimer?.cancel();
    if (!_visible) setState(() => _visible = true);
    _hideTimer = Timer(_hideAfter, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _hide() {
    _hideTimer?.cancel();
    setState(() => _visible = false);
  }

  void _seekBy(Duration offset) {
    final state = _player.state;
    var target = state.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (state.duration > Duration.zero && target > state.duration) {
      target = state.duration;
    }
    _player.seek(target);
    _show();
  }

  void _volumeBy(double delta) {
    _player.setVolume((_player.state.volume + delta).clamp(0, 100));
    _show();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // Répétition (touche maintenue) : seulement pour avancer, reculer et le
    // volume ; un appui maintenu sur Espace ne doit pas alterner sans fin.
    final repeat = event is KeyRepeatEvent;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-_step);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(_step);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _volumeBy(5);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _volumeBy(-5);
    } else if (repeat) {
      return KeyEventResult.ignored;
    } else if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _player.playOrPause();
      _show();
    } else if (key == LogicalKeyboardKey.keyF) {
      widget.onToggleFullscreen();
    } else if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      widget.fullscreen ? widget.onToggleFullscreen() : widget.onExit();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _onTapUp(TapUpDetails details) {
    if (details.kind == PointerDeviceKind.mouse) {
      _player.playOrPause();
      _show();
    } else {
      _visible ? _hide() : _show();
    }
  }

  void _onDoubleTapDown(TapDownDetails details) {
    if (details.kind == PointerDeviceKind.mouse) {
      widget.onToggleFullscreen();
      return;
    }
    final width = context.size?.width ?? 0;
    _seekBy(details.localPosition.dx < width / 2 ? -_step : _step);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: _visible ? MouseCursor.defer : SystemMouseCursors.none,
        onHover: (_) => _show(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _onTapUp,
          onDoubleTapDown: _onDoubleTapDown,
          // Requis pour que onDoubleTapDown soit appelé.
          onDoubleTap: () {},
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_visible,
              child: Theme(
                data: ThemeData(
                  brightness: Brightness.dark,
                  colorSchemeSeed: Colors.deepPurple,
                ),
                child: _bars(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bars(BuildContext context) {
    const shade = [Colors.black87, Colors.transparent];
    return Column(
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: shade,
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Retour',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onExit,
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: shade,
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ProgressBar(player: _player, onSeek: _show),
                  _buttons(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buttons() {
    return FocusTraversalGroup(
      child: Row(
        children: [
          StreamBuilder<bool>(
            stream: _player.stream.playing,
            initialData: _player.state.playing,
            builder: (context, snapshot) {
              final playing = snapshot.data ?? false;
              return IconButton(
                tooltip: playing ? 'Pause' : 'Lecture',
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                onPressed: () {
                  _player.playOrPause();
                  _show();
                },
              );
            },
          ),
          IconButton(
            tooltip: 'Reculer de 10 s',
            icon: const Icon(Icons.replay_10),
            onPressed: () => _seekBy(-_step),
          ),
          IconButton(
            tooltip: 'Avancer de 10 s',
            icon: const Icon(Icons.forward_10),
            onPressed: () => _seekBy(_step),
          ),
          _VolumeButton(player: _player, onChanged: _show),
          const Spacer(),
          _TracksMenu(player: _player, onOpened: _show),
          IconButton(
            tooltip: widget.fill ? 'Image entière' : 'Remplir l\'écran',
            icon: Icon(widget.fill ? Icons.fit_screen : Icons.crop_free),
            onPressed: () {
              widget.onToggleFill();
              _show();
            },
          ),
          IconButton(
            tooltip: widget.fullscreen
                ? 'Quitter le plein écran'
                : 'Plein écran',
            icon: Icon(
              widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            ),
            onPressed: widget.onToggleFullscreen,
          ),
        ],
      ),
    );
  }
}

/// Barre de progression : temps écoulé, curseur, durée.
class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.player, required this.onSeek});

  final Player player;
  final VoidCallback onSeek;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  // Position tenue par le doigt ou la souris pendant un glisser : la vidéo
  // ne cherche qu'au relâchement.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      initialData: player.state.duration,
      builder: (context, duration) {
        final total = duration.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, position) {
            final max = total.inMilliseconds.toDouble();
            final current =
                _dragging ??
                (position.data ?? Duration.zero).inMilliseconds
                    .clamp(0, total.inMilliseconds)
                    .toDouble();
            return Row(
              children: [
                Text(formatTime(Duration(milliseconds: current.round()))),
                Expanded(
                  child: Slider(
                    value: max > 0 ? current : 0,
                    max: max > 0 ? max : 1,
                    onChanged: max > 0
                        ? (value) {
                            setState(() => _dragging = value);
                            widget.onSeek();
                          }
                        : null,
                    onChangeEnd: (value) {
                      player.seek(Duration(milliseconds: value.round()));
                      setState(() => _dragging = null);
                    },
                  ),
                ),
                Text(formatTime(total)),
              ],
            );
          },
        );
      },
    );
  }
}

class _VolumeButton extends StatelessWidget {
  const _VolumeButton({required this.player, required this.onChanged});

  final Player player;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (context, snapshot) {
        final volume = snapshot.data ?? 100;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: volume == 0 ? 'Remettre le son' : 'Couper le son',
              icon: Icon(volume == 0 ? Icons.volume_off : Icons.volume_up),
              onPressed: () {
                player.setVolume(volume == 0 ? 100 : 0);
                onChanged();
              },
            ),
            SizedBox(
              width: 100,
              child: Slider(
                value: volume.clamp(0, 100),
                max: 100,
                onChanged: (value) {
                  player.setVolume(value);
                  onChanged();
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Menus Audio et Sous-titres, d'après les pistes du fichier.
class _TracksMenu extends StatelessWidget {
  const _TracksMenu({required this.player, required this.onOpened});

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
                enabled: subtitles.isNotEmpty,
                onOpened: onOpened,
                onSelected: player.setSubtitleTrack,
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: SubtitleTrack.no(),
                    checked:
                        selectedSubtitle == null || selectedSubtitle == 'no',
                    child: const Text('Désactivés'),
                  ),
                  for (final (index, track) in subtitles.indexed)
                    CheckedPopupMenuItem(
                      value: track,
                      checked: track.id == selectedSubtitle,
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

/// `1:05:09`, ou `5:09` sous une heure.
String formatTime(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  final seconds = d.inSeconds % 60;
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '$minutes:${two(seconds)}';
}
