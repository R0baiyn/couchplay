import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../accounts/account_store.dart';
import '../accounts/server_session.dart';
import '../server/models.dart';
import 'playback.dart';
import 'player_controls.dart';

/// Ouvre le lecteur sur un film ou un épisode du compte actif.
Future<void> openPlayer(
  BuildContext context,
  WidgetRef ref, {
  required ContentKind kind,
  required String id,
  required String extension,
  required String title,
}) {
  // Un double clic sur « Lecture » ne doit pas empiler deux lecteurs.
  if (ModalRoute.of(context)?.isCurrent == false) return Future.value();
  final account = ref.read(activeAccountProvider);
  final client = ref.read(serverClientProvider);
  if (account == null || client == null) return Future.value();
  final request = PlayRequest(
    title: title,
    url: client.streamUri(kind, id, extension),
    userAgent: account.userAgent,
    secrets: [account.username, account.password],
  );
  return Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => PlayerScreen(request: request)),
  );
}

/// Lecture plein cadre. Quitter l'écran arrête le flux.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.request});

  final PlayRequest request;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Playback _playback = ref.read(playbackProvider);
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<bool>? _completed;

  // Sur mobile, le lecteur est toujours en plein écran paysage.
  static final _mobile = Platform.isAndroid || Platform.isIOS;

  /// Ticket de notre ouverture : l'arrêt de cet écran ne coupe que notre flux.
  int? _ticket;
  var _opening = true;
  String? _error;
  var _fill = false;
  var _fullscreen = false;

  @override
  void initState() {
    super.initState();
    if (_mobile) _setFullscreen(true);
    _lifecycle = AppLifecycleListener(onHide: _onHide);
    _completed = _playback.player.stream.completed.listen(_onCompleted);
    _open();
  }

  /// Sur mobile, passer l'app en arrière-plan arrête le flux tout de suite
  /// (l'animation de sortie ne tourne pas en arrière-plan, donc on n'attend
  /// pas la fermeture de l'écran), puis quitte le lecteur, menu ouvert ou non.
  void _onHide() {
    if (!_mobile || !mounted) return;
    unawaited(_playback.stop(_ticket));
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route != null && route.isActive) {
      navigator.popUntil((r) => r == route);
      navigator.pop();
    }
  }

  /// Fin du fichier bien avant la fin du film : le serveur a coupé (autre
  /// appareil, réseau). On le dit au lieu de laisser une image figée.
  void _onCompleted(bool completed) {
    final state = _playback.player.state;
    final cutShort =
        state.duration > Duration.zero &&
        state.position < state.duration - const Duration(seconds: 30);
    if (completed && cutShort && !_opening && mounted) {
      _resumeAt = state.position;
      setState(
        () => _error =
            'La lecture s\'est interrompue : le serveur a coupé la connexion.',
      );
    }
  }

  /// Position où reprendre après une coupure.
  Duration? _resumeAt;

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    final opening = _playback.open(widget.request);
    _ticket = _playback.ticket;
    try {
      await opening;
      if (_resumeAt case final position?) {
        await _playback.player.seek(position);
        _resumeAt = null;
      }
    } on PlaybackFailed catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _setFullscreen(bool on) async {
    setState(() => _fullscreen = on);
    await (on ? defaultEnterNativeFullscreen() : defaultExitNativeFullscreen());
  }

  void _exit() => Navigator.maybePop(context);

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_completed?.cancel());
    unawaited(_playback.stop(_ticket));
    if (_fullscreen) unawaited(defaultExitNativeFullscreen());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: _playback.controller,
            controls: NoVideoControls,
            fit: _fill ? BoxFit.cover : BoxFit.contain,
            // Le lecteur gère lui-même l'arrière-plan (voir _onHide).
            pauseUponEnteringBackgroundMode: false,
          ),
          if (error != null)
            // Échap : quitte d'abord le plein écran, comme dans les contrôles.
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    _fullscreen && !_mobile ? _setFullscreen(false) : _exit(),
              },
              child: _ErrorPanel(message: error, onRetry: _open, onExit: _exit),
            )
          else ...[
            PlayerControls(
              player: _playback.player,
              title: widget.request.title,
              fill: _fill,
              onToggleFill: () => setState(() => _fill = !_fill),
              // Sur mobile, toujours en plein écran : pas de bouton.
              fullscreen: _mobile ? null : _fullscreen,
              onToggleFullscreen: () {
                if (!_mobile) _setFullscreen(!_fullscreen);
              },
              onExit: _exit,
            ),
            if (_opening)
              const IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.onRetry,
    required this.onExit,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.deepPurple,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: onExit,
                    child: const Text('Retour'),
                  ),
                  FilledButton(
                    autofocus: true,
                    onPressed: onRetry,
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
