import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../format.dart';

/// Barre de progression : temps écoulé, curseur, durée.
class PlayerProgressBar extends StatefulWidget {
  const PlayerProgressBar({
    super.key,
    required this.player,
    required this.onSeek,
  });

  final Player player;
  final VoidCallback onSeek;

  @override
  State<PlayerProgressBar> createState() => PlayerProgressBarState();
}

class PlayerProgressBarState extends State<PlayerProgressBar> {
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

  // ← → avec le focus : 10 s par appui ; maintenue, la touche se répète et
  // le pas grandit. Seuils comptés en répétitions (≈ 20 par seconde sous
  // Android, ≈ 30 sous Windows), car les tests n'ont pas d'horloge.
  static const _keyStep = 10;
  static const _fasterAfterRepeats = 10;
  static const _fasterStep = 30;
  static const _fastestAfterRepeats = 30;
  static const _fastestStep = 60;

  // Reçoit ← → avant les raccourcis du Slider (5 % du film par appui).
  late final _focus = FocusNode(debugLabel: 'progression', onKeyEvent: _onKey);
  var _repeats = 0;

  @override
  void dispose() {
    _release?.cancel();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final sign = key == LogicalKeyboardKey.arrowLeft
        ? -1
        : key == LogicalKeyboardKey.arrowRight
        ? 1
        : 0;
    final state = widget.player.state;
    final max = state.duration.inSeconds;
    if (sign == 0 || event is KeyUpEvent || max <= 0) {
      return KeyEventResult.ignored;
    }
    _repeats = event is KeyRepeatEvent ? _repeats + 1 : 0;
    final step = _repeats >= _fastestAfterRepeats
        ? _fastestStep
        : _repeats >= _fasterAfterRepeats
        ? _fasterStep
        : _keyStep;
    // Depuis la position visée, pas celle de la vidéo, en retard pendant un
    // maintien.
    final from = _held ?? state.position.inSeconds.toDouble();
    _seekTo((from + sign * step).clamp(0, max).toDouble());
    return KeyEventResult.handled;
  }

  void _seekTo(double seconds) {
    widget.player.seek(Duration(seconds: seconds.round()));
    _release?.cancel();
    setState(() => _held = seconds);
    _release = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _held = null);
    });
    widget.onSeek();
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
                Text(
                  formatTime(Duration(seconds: current.round())),
                  key: const ValueKey('player.elapsed'),
                ),
                Expanded(
                  child: Slider(
                    key: const ValueKey('player.progress'),
                    focusNode: _focus,
                    value: max > 0 ? current.clamp(0, max) : 0,
                    max: max > 0 ? max : 1,
                    onChanged: max > 0
                        ? (value) {
                            _release?.cancel();
                            setState(() => _held = value);
                            widget.onSeek();
                          }
                        : null,
                    onChangeEnd: _seekTo,
                  ),
                ),
                Text(
                  formatTime(Duration(seconds: max.round())),
                  key: const ValueKey('player.duration'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
