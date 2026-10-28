import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

/// Contrôles du lecteur, par-dessus la vidéo.
///
/// - Souris : clic = pause, double-clic = plein écran (sur l'image, pas sur
///   les boutons) ; contrôles et curseur se masquent après 3 s sans
///   mouvement, sauf en pause ou quand la souris est sur les barres.
/// - Toucher : un toucher affiche ou masque les contrôles, un double toucher
///   à gauche ou à droite recule ou avance de 10 s.
/// - Clavier : Espace ou Entrée (pause), ← → (±10 s), ↑ ↓ (volume), F (plein
///   écran), Échap (quitte le plein écran, puis le lecteur). Tab passe aux
///   boutons ; là, les flèches passent d'un bouton à l'autre.
/// - Télécommande (Android) : OK (pause), ← → (±10 s), ↑ ↓ vont aux boutons,
///   où les flèches passent de l'un à l'autre ; retour quitte le lecteur.
///   Quand les contrôles se masquent, le focus revient sur l'image.
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

  /// `null` : pas de bouton plein écran (mobile, toujours en plein écran).
  final bool? fullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onExit;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  static const _hideAfter = Duration(seconds: 3);
  static const _step = Duration(seconds: 10);

  var _visible = true;
  var _overBars = false;
  Timer? _hideTimer;

  /// L'image, qui reçoit les touches, et le bouton lecture, où ↑ ↓ mènent
  /// sur Android (le volume est celui de l'appareil).
  final _videoFocus = FocusNode(debugLabel: 'vidéo');
  final _playFocus = FocusNode(debugLabel: 'lecture');

  Player get _player => widget.player;

  @override
  void initState() {
    super.initState();
    _show();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _videoFocus.dispose();
    _playFocus.dispose();
    super.dispose();
  }

  /// Affiche les contrôles et relance le compte à rebours.
  void _show() {
    _hideTimer?.cancel();
    if (!_visible) setState(() => _visible = true);
    _hideTimer = Timer(_hideAfter, _autoHide);
  }

  // Pas de masquage en pause ni sous la souris : on relance l'attente.
  void _autoHide() {
    if (!mounted) return;
    if (!_player.state.playing || _overBars) {
      _hideTimer = Timer(_hideAfter, _autoHide);
      return;
    }
    _hide();
  }

  /// Masque les contrôles. Un bouton qui avait le focus le rend à l'image :
  /// les flèches y reprennent leur rôle (±10 s).
  void _hide() {
    _hideTimer?.cancel();
    if (_videoFocus.hasFocus && !_videoFocus.hasPrimaryFocus) {
      _videoFocus.requestFocus();
    }
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
    // Toute touche réaffiche les contrôles : Tab ne doit pas activer un
    // bouton invisible.
    _show();
    final key = event.logicalKey;
    final repeat = event is KeyRepeatEvent;
    // Sur un bouton (Tab), flèches et Espace gardent leur rôle habituel :
    // passer d'un bouton à l'autre, activer le bouton.
    final onVideo = node.hasPrimaryFocus;
    final vertical =
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;

    if (onVideo && key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-_step);
    } else if (onVideo && key == LogicalKeyboardKey.arrowRight) {
      _seekBy(_step);
    } else if (onVideo &&
        vertical &&
        defaultTargetPlatform == TargetPlatform.android) {
      _playFocus.requestFocus();
    } else if (onVideo && key == LogicalKeyboardKey.arrowUp) {
      _volumeBy(5);
    } else if (onVideo && key == LogicalKeyboardKey.arrowDown) {
      _volumeBy(-5);
    } else if ((onVideo &&
            (key == LogicalKeyboardKey.space ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.select)) ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      // Maintenue, la touche n'alterne pas sans fin.
      if (!repeat) _player.playOrPause();
    } else if (key == LogicalKeyboardKey.keyF) {
      if (!repeat && widget.fullscreen != null) widget.onToggleFullscreen();
    } else if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      // Maintenue, Échap ne quitte pas le lecteur dans la foulée.
      if (!repeat) {
        widget.fullscreen ?? false
            ? widget.onToggleFullscreen()
            : widget.onExit();
      }
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
      if (widget.fullscreen != null) widget.onToggleFullscreen();
      return;
    }
    final width = context.size?.width ?? 0;
    _seekBy(details.localPosition.dx < width / 2 ? -_step : _step);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _videoFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: _visible ? MouseCursor.defer : SystemMouseCursors.none,
        onHover: (_) => _show(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Gestes de l'image, sous les barres : les boutons et curseurs
            // reçoivent leurs clics directement, sans délai ni double-clic
            // détourné.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _onTapUp,
              onDoubleTapDown: _onDoubleTapDown,
              // Requis pour que onDoubleTapDown soit appelé.
              onDoubleTap: () {},
            ),
            AnimatedOpacity(
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
          ],
        ),
      ),
    );
  }

  Widget _bars(BuildContext context) {
    const shade = [Colors.black87, Colors.transparent];
    Widget bar(Widget child) => MouseRegion(
      onEnter: (_) => _overBars = true,
      onExit: (_) => _overBars = false,
      child: child,
    );
    return Column(
      children: [
        bar(
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
                  _Resolution(player: _player),
                ],
              ),
            ),
          ),
        ),
        // Laisse passer clics et touchers vers les gestes de l'image.
        const Spacer(),
        bar(
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
        ),
      ],
    );
  }

  Widget _buttons() {
    final fullscreen = widget.fullscreen;
    return FocusTraversalGroup(
      child: Row(
        children: [
          StreamBuilder<bool>(
            stream: _player.stream.playing,
            initialData: _player.state.playing,
            builder: (context, snapshot) {
              final playing = snapshot.data ?? false;
              return IconButton(
                focusNode: _playFocus,
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
          if (fullscreen != null)
            IconButton(
              tooltip: fullscreen ? 'Quitter le plein écran' : 'Plein écran',
              icon: Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
              onPressed: widget.onToggleFullscreen,
            ),
        ],
      ),
    );
  }
}

/// Taille réelle de l'image décodée (« 3840 × 1600 ») : dit quelle version
/// d'un film est lue, quoi qu'annonce son nom.
class _Resolution extends StatelessWidget {
  const _Resolution({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int?>(
      stream: player.stream.width,
      initialData: player.state.width,
      builder: (context, width) => StreamBuilder<int?>(
        stream: player.stream.height,
        initialData: player.state.height,
        builder: (context, height) {
          final (w, h) = (width.data, height.data);
          if (w == null || h == null || w == 0 || h == 0) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '$w × $h',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          );
        },
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
  // Une valeur par seconde au lieu d'une par image décodée : la barre ne
  // se reconstruit qu'une fois par seconde. Créés une fois, pour ne pas se
  // réabonner à chaque reconstruction des contrôles.
  late final Stream<int> _seconds = widget.player.stream.position
      .map((p) => p.inSeconds)
      .distinct();
  late final Stream<int> _total = widget.player.stream.duration
      .map((d) => d.inSeconds)
      .distinct();

  // Position tenue pendant un glisser, puis jusqu'à ce que la vidéo l'ait
  // rejointe : le curseur ne revient pas en arrière un instant.
  double? _held;
  Timer? _release;

  @override
  void dispose() {
    _release?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return StreamBuilder<int>(
      stream: _total,
      initialData: player.state.duration.inSeconds,
      builder: (context, total) {
        final max = (total.data ?? 0).toDouble();
        return StreamBuilder<int>(
          stream: _seconds,
          initialData: player.state.position.inSeconds,
          builder: (context, position) {
            final current =
                _held ?? (position.data ?? 0).clamp(0, max).toDouble();
            return Row(
              children: [
                Text(formatTime(Duration(seconds: current.round()))),
                Expanded(
                  child: Slider(
                    value: max > 0 ? current.clamp(0, max) : 0,
                    max: max > 0 ? max : 1,
                    onChanged: max > 0
                        ? (value) {
                            _release?.cancel();
                            setState(() => _held = value);
                            widget.onSeek();
                          }
                        : null,
                    onChangeEnd: (value) {
                      player.seek(Duration(seconds: value.round()));
                      _release = Timer(const Duration(milliseconds: 800), () {
                        if (mounted) setState(() => _held = null);
                      });
                    },
                  ),
                ),
                Text(formatTime(Duration(seconds: max.round()))),
              ],
            );
          },
        );
      },
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

/// Ajoute à la lecture en cours les sous-titres d'un fichier choisi par
/// l'utilisateur (.srt, .ass, .vtt…). Le texte est passé à mpv plutôt que
/// le chemin : sous Android, le fichier choisi n'a pas toujours de chemin.
Future<void> loadSubtitleFile(Player player) async {
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
                    onTap: () => loadSubtitleFile(player),
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
