import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'player_bars.dart';
import 'player_buttons.dart';
import 'player_progress_bar.dart';

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
/// - Sur l'image, contrôles masqués, le premier ← → les affiche sans bouger
///   la vidéo ; les suivants sautent. OK, Espace et les touches média
///   agissent dès le premier appui.
/// - Touches média, où que soit le focus : ⏪ ⏩ (±10 s), lecture, pause,
///   lecture/pause.
/// - Barre de progression avec le focus : ← → (±10 s) ; maintenue, le pas
///   passe à 30 s puis à 60 s.
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
    this.volume = true,
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

  /// Bouton et curseur du volume. Pas sur TV : la télécommande règle celui
  /// de la TV, et le curseur retenait ← →.
  final bool volume;

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
    // Lu avant _show() : contrôles masqués, ← → les affichent seulement.
    final wasVisible = _visible;
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
      if (wasVisible) _seekBy(-_step);
    } else if (onVideo && key == LogicalKeyboardKey.arrowRight) {
      if (wasVisible) _seekBy(_step);
    } else if (key == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-_step);
    } else if (key == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(_step);
    } else if (key == LogicalKeyboardKey.mediaPlay) {
      if (!repeat) _player.play();
    } else if (key == LogicalKeyboardKey.mediaPause) {
      if (!repeat) _player.pause();
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
    } else if (key == LogicalKeyboardKey.escape) {
      // Retour (Android, télécommande) n'est pas traité ici : Android ferme
      // déjà le lecteur par son retour système, le traiter aussi fermait
      // l'écran d'en dessous. Maintenue, Échap ne quitte pas le lecteur dans
      // la foulée.
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
      // Pas une étape des flèches : grande comme l'écran, l'image serait
      // toujours « au-dessus » d'un bouton. Elle reprend le focus quand les
      // contrôles se masquent.
      skipTraversal: true,
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
              key: const ValueKey('player.video'),
              behavior: HitTestBehavior.opaque,
              onTapUp: _onTapUp,
              onDoubleTapDown: _onDoubleTapDown,
              // Requis pour que onDoubleTapDown soit appelé.
              onDoubleTap: () {},
            ),
            AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(ignoring: !_visible, child: _bars()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bars() => PlayerBars(
    player: _player,
    title: widget.title,
    onExit: widget.onExit,
    onOver: (over) => _overBars = over,
    bottom: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerProgressBar(player: _player, onSeek: _show),
        PlayerButtons(
          player: _player,
          playFocus: _playFocus,
          fill: widget.fill,
          fullscreen: widget.fullscreen,
          volume: widget.volume,
          onActivity: _show,
          onRewind: () => _seekBy(-_step),
          onForward: () => _seekBy(_step),
          onToggleFill: widget.onToggleFill,
          onToggleFullscreen: widget.onToggleFullscreen,
        ),
      ],
    ),
  );
}
