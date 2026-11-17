import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../server/status_views.dart';
import '../library/library.dart';
import 'next_episode_panel.dart';
import 'playback.dart';
import 'player_controls.dart';

/// Ce que le lecteur montre : la vidéo, puis les contrôles, le chargement et
/// l'encart de l'épisode suivant, ou l'erreur. L'état reste dans
/// `PlayerScreen`, qui crée et libère les nœuds de focus.
class PlayerView extends StatelessWidget {
  const PlayerView({
    super.key,
    required this.playback,
    required this.title,
    required this.fill,
    required this.fullscreen,
    required this.volume,
    required this.opening,
    required this.error,
    required this.next,
    required this.secondsLeft,
    required this.playNowFocus,
    required this.onToggleFill,
    required this.onToggleFullscreen,
    required this.onExit,
    required this.onBack,
    required this.onRetry,
    required this.onPlayNext,
    required this.onCancelNext,
  });

  final Playback playback;
  final String title;
  final bool fill;

  /// `null` : pas de bouton plein écran (mobile).
  final bool? fullscreen;
  final bool volume;
  final bool opening;
  final String? error;
  final ({PlayItem item, String? image})? next;
  final int secondsLeft;
  final FocusNode playNowFocus;
  final VoidCallback onToggleFill;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onExit;

  /// Échap hors des contrôles : plein écran d'abord, puis le lecteur.
  final VoidCallback onBack;
  final VoidCallback onRetry;
  final VoidCallback onPlayNext;
  final VoidCallback onCancelNext;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    final next = this.next;
    final escape = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): onBack,
    };
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: playback.controller,
            controls: NoVideoControls,
            fit: fill ? BoxFit.cover : BoxFit.contain,
            // Le lecteur gère lui-même l'arrière-plan (voir `_onHide`).
            pauseUponEnteringBackgroundMode: false,
          ),
          if (error != null)
            CallbackShortcuts(
              bindings: escape,
              // Texte blanc sur le fond noir du lecteur.
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: ErrorView(
                  key: const ValueKey('player.error'),
                  message: error,
                  onRetry: onRetry,
                  onExit: onExit,
                ),
              ),
            )
          else ...[
            PlayerControls(
              player: playback.player,
              title: title,
              fill: fill,
              onToggleFill: onToggleFill,
              fullscreen: fullscreen,
              onToggleFullscreen: onToggleFullscreen,
              onExit: onExit,
              volume: volume,
            ),
            if (opening)
              const IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
            if (next != null)
              Align(
                alignment: Alignment.bottomRight,
                // Le focus est sur l'encart, hors des contrôles : Échap doit
                // quand même quitter.
                child: CallbackShortcuts(
                  bindings: escape,
                  child: NextEpisodePanel(
                    title: next.item.title,
                    image: next.image ?? next.item.poster,
                    secondsLeft: secondsLeft,
                    playNowFocus: playNowFocus,
                    onPlayNow: onPlayNext,
                    onCancel: onCancelNext,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
