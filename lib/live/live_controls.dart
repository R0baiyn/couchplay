import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../player/player_bars.dart';
import '../player/player_tracks.dart';
import 'channel.dart';
import 'channel_favorite.dart';
import 'live_banner.dart';
import 'live_tuner.dart';

/// Contrôles du lecteur du direct, par-dessus l'image : ni barre de temps ni
/// ±10 s, un bandeau de la chaîne (seul, ou dans les barres chaque fois
/// qu'elles s'affichent) et le zapping en aperçu (`LiveTuner`).
///
/// - ↑ ↓ : chaîne précédente ou suivante ; CH+ CH− aussi, où que soit le
///   focus. Pendant l'aperçu, OK, Entrée ou un toucher du bandeau ouvrent
///   tout de suite la chaîne affichée. Sur TV, barres affichées, ↑ ↓ vont
///   aux boutons (les flèches y passent de l'un à l'autre) ; un zapping
///   n'affiche pas les barres, sinon le 2e appui irait aux boutons.
/// - Hors aperçu, OK et Entrée ; Espace, ← → : affichent les barres, le focus sur le premier
///   bouton (lecture / pause : une autre app qui prend le son met en pause,
///   D-071). Touches média : lecture, pause.
/// - Souris : survol = barres ; double-clic = plein écran. Toucher : affiche
///   ou masque les barres.
/// - F : plein écran ; Échap : quitte le plein écran, puis le lecteur ; la
///   flèche retour des barres quitte le lecteur, même en plein écran.
class LiveControls extends StatefulWidget {
  const LiveControls({
    super.key,
    required this.tuner,
    required this.player,
    required this.television,
    required this.fill,
    required this.onToggleFill,
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.onExit,
  });

  final LiveTuner tuner;
  final Player player;
  final bool television;
  final bool fill;
  final VoidCallback onToggleFill;

  /// `null` : pas de bouton plein écran (mobile).
  final bool? fullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onExit;

  @override
  State<LiveControls> createState() => _LiveControlsState();
}

class _LiveControlsState extends State<LiveControls> {
  final _bars = AutoHide(const Duration(seconds: 3));
  final _videoFocus = FocusNode(debugLabel: 'vidéo du direct');
  final _firstButton = FocusNode(debugLabel: 'lecture');

  LiveTuner get _tuner => widget.tuner;

  @override
  void initState() {
    super.initState();
    _bars.addListener(_onBars);
  }

  @override
  void dispose() {
    _bars.dispose();
    _videoFocus.dispose();
    _firstButton.dispose();
    super.dispose();
  }

  /// Barres masquées : un bouton qui avait le focus le rend à l'image, où
  /// ↑ ↓ zappent de nouveau.
  void _onBars() {
    if (!_bars.visible &&
        _videoFocus.hasFocus &&
        !_videoFocus.hasPrimaryFocus) {
      _videoFocus.requestFocus();
    }
    setState(() {});
  }

  void _focusButtons() {
    _bars.show();
    _firstButton.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final repeat = event is KeyRepeatEvent;
    final onVideo = node.hasPrimaryFocus;
    final down = key == LogicalKeyboardKey.arrowDown;
    if (key == LogicalKeyboardKey.channelUp) {
      _tuner.zap(1);
    } else if (key == LogicalKeyboardKey.channelDown) {
      _tuner.zap(-1);
    } else if (onVideo && (down || key == LogicalKeyboardKey.arrowUp)) {
      widget.television && _bars.visible
          ? _focusButtons()
          : _tuner.zap(down ? 1 : -1);
    } else if (onVideo &&
        (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter)) {
      if (!repeat && !_tuner.confirm()) _focusButtons();
    } else if (onVideo &&
        (key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      if (!repeat) _focusButtons();
    } else if (key == LogicalKeyboardKey.mediaPlayPause) {
      if (!repeat) widget.player.playOrPause();
    } else if (key == LogicalKeyboardKey.mediaPlay) {
      if (!repeat) widget.player.play();
    } else if (key == LogicalKeyboardKey.mediaPause) {
      if (!repeat) widget.player.pause();
    } else if (key == LogicalKeyboardKey.keyF) {
      if (!repeat && widget.fullscreen != null) widget.onToggleFullscreen();
    } else if (key == LogicalKeyboardKey.escape) {
      // Retour (Android) n'est pas traité ici : le retour système ferme
      // déjà le lecteur.
      if (!repeat) {
        widget.fullscreen ?? false
            ? widget.onToggleFullscreen()
            : widget.onExit();
      }
    } else {
      // Sur un bouton : les barres restent, la touche garde son rôle.
      if (!onVideo) _bars.show();
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _toggleBars() => _bars.visible ? _bars.hide() : _bars.show();

  /// Pendant l'aperçu, ouvre la chaîne affichée ; sinon comme l'image.
  Widget _banner(Channel channel) => GestureDetector(
    onTap: () {
      if (!_tuner.confirm()) _toggleBars();
    },
    child: LiveBanner(channel: channel),
  );

  void _onDoubleTapDown(TapDownDetails details) {
    if (details.kind == PointerDeviceKind.mouse && widget.fullscreen != null) {
      widget.onToggleFullscreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final channel = _tuner.channel;
    final visible = _bars.visible;
    return Focus(
      focusNode: _videoFocus,
      autofocus: true,
      // Pas une étape des flèches : elle reprend le focus quand les barres
      // se masquent.
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: visible ? MouseCursor.defer : SystemMouseCursors.none,
        onHover: (_) => _bars.show(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: const ValueKey('live.player.video'),
              behavior: HitTestBehavior.opaque,
              onTap: _toggleBars,
              onDoubleTapDown: _onDoubleTapDown,
              // Requis pour que onDoubleTapDown soit appelé.
              onDoubleTap: () {},
            ),
            AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !visible,
                child: PlayerBars(
                  player: widget.player,
                  title: channelLabel(channel),
                  onExit: widget.onExit,
                  onOver: (over) => _bars.hold = over,
                  bottom: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Construit seulement barres affichées : pas de
                      // bandeau caché sous l'opacité 0.
                      if (visible) _banner(channel),
                      _buttons(),
                    ],
                  ),
                ),
              ),
            ),
            // Barres masquées : le bandeau seul, à l'ouverture et au zapping.
            ListenableBuilder(
              listenable: _tuner.banner,
              builder: (context, _) => _tuner.banner.visible && !visible
                  ? Align(
                      alignment: Alignment.bottomLeft,
                      child: SafeArea(child: _banner(channel)),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buttons() {
    final fullscreen = widget.fullscreen;
    return FocusTraversalGroup(
      child: Row(
        children: [
          StreamBuilder<bool>(
            stream: widget.player.stream.playing,
            initialData: widget.player.state.playing,
            builder: (context, snapshot) {
              final playing = snapshot.data ?? false;
              return IconButton(
                key: const ValueKey('live.player.playPause'),
                focusNode: _firstButton,
                tooltip: playing ? 'Pause' : 'Lecture',
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                onPressed: () {
                  widget.player.playOrPause();
                  _bars.show();
                },
              );
            },
          ),
          IconButton(
            key: const ValueKey('live.player.previous'),
            tooltip: 'Chaîne précédente',
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: () {
              _tuner.zap(-1);
              _bars.show();
            },
          ),
          IconButton(
            key: const ValueKey('live.player.next'),
            tooltip: 'Chaîne suivante',
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () {
              _tuner.zap(1);
              _bars.show();
            },
          ),
          ChannelFavoriteButton(channel: _tuner.channel, onPressed: _bars.show),
          const Spacer(),
          TracksMenu(player: widget.player, onOpened: _bars.show),
          IconButton(
            key: const ValueKey('live.player.fill'),
            tooltip: widget.fill ? 'Image entière' : 'Remplir l\'écran',
            icon: Icon(widget.fill ? Icons.fit_screen : Icons.crop_free),
            onPressed: () {
              widget.onToggleFill();
              _bars.show();
            },
          ),
          if (fullscreen != null)
            IconButton(
              key: const ValueKey('live.player.fullscreen'),
              tooltip: fullscreen ? 'Quitter le plein écran' : 'Plein écran',
              icon: Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
              onPressed: widget.onToggleFullscreen,
            ),
        ],
      ),
    );
  }
}
