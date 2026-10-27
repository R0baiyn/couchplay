import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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

  // Sur mobile, le lecteur est toujours en plein écran paysage.
  static final _mobile = Platform.isAndroid || Platform.isIOS;

  var _opening = true;
  PlaybackFailed? _error;
  var _fill = false;
  var _fullscreen = false;

  @override
  void initState() {
    super.initState();
    if (_mobile) _setFullscreen(true);
    // Sur mobile, passer l'app en arrière-plan quitte le lecteur : le flux
    // s'arrête au lieu d'occuper l'unique connexion de l'abonnement.
    _lifecycle = AppLifecycleListener(
      onHide: () {
        if (_mobile && mounted) Navigator.maybePop(context);
      },
    );
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await _playback.open(widget.request);
    } on PlaybackFailed catch (e) {
      if (mounted) setState(() => _error = e);
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
    unawaited(_playback.stop());
    if (_fullscreen) unawaited(defaultExitNativeFullscreen());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: _playback.controller,
            controls: NoVideoControls,
            fit: _fill ? BoxFit.cover : BoxFit.contain,
            // Le lecteur gère lui-même l'arrière-plan (voir initState).
            pauseUponEnteringBackgroundMode: false,
          ),
          if (_error case final error?)
            _ErrorPanel(message: error.message, onRetry: _open, onExit: _exit)
          else ...[
            PlayerControls(
              player: _playback.player,
              title: widget.request.title,
              fill: _fill,
              onToggleFill: () => setState(() => _fill = !_fill),
              fullscreen: _fullscreen && !_mobile,
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
