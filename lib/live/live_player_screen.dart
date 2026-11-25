import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../orientation.dart';
import '../player/audio_focus.dart';
import '../player/mobile_fullscreen.dart';
import '../player/playback.dart';
import '../player/player_request.dart';
import '../player/player_view.dart';
import '../player/stream_holds.dart';
import '../server/status_views.dart';
import '../television.dart';
import 'channel.dart';
import 'channel_favorite.dart';
import 'live_banner.dart';
import 'live_controls.dart';
import 'live_tuner.dart';

/// Lecteur du direct : la chaîne [channel], zapping dans [channels] (la liste
/// d'où l'on vient). Chaque chaîne qui démarre va en tête des récentes. Un seul flux à la fois (`Playback`), téléchargements
/// mis en pause si le serveur refuse le flux pendant l'un d'eux (D-036).
/// Fermé, il rend la dernière chaîne affichée à qui l'a ouvert.
class LivePlayerScreen extends ConsumerStatefulWidget {
  const LivePlayerScreen({
    super.key,
    required this.channel,
    required this.channels,
  });

  final Channel channel;
  final List<Channel> channels;

  @override
  ConsumerState<LivePlayerScreen> createState() => _LivePlayerScreenState();
}

class _LivePlayerScreenState extends ConsumerState<LivePlayerScreen> {
  late final Playback _playback = ref.read(playbackProvider);

  /// Lus dans initState : `ref` n'est plus utilisable dans dispose.
  late final StreamHolds _holds;
  late final LiveTuner _tuner;
  late final AudioFocus _audio;
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<bool> _completed;

  static final _mobile = Platform.isAndroid || Platform.isIOS;

  /// Ticket de notre dernière ouverture : l'arrêt de cet écran ne coupe que
  /// notre flux.
  int? _ticket;
  var _fill = false;
  var _fullscreen = false;

  @override
  void initState() {
    super.initState();
    _holds = StreamHolds.read(ref);
    _tuner = LiveTuner(
      channels: widget.channels,
      start: widget.channel,
      open: _open,
      // Une chaîne a vraiment démarré, d'où que vienne le lecteur (liste,
      // grille, accueil, recherche) : en tête des récentes du compte.
      onWatched: (channel) {
        if (mounted) recordRecentChannel(ref, channel);
      },
    );
    // Un direct ne finit pas : une fin de fichier est une coupure.
    _completed = _playback.player.stream.completed.listen((completed) {
      if (completed && _ticket == _playback.ticket) _tuner.lost();
    });
    _audio = AudioFocus(
      playing: _playback.player.stream.playing,
      pause: _playback.player.pause,
    );
    _lifecycle = AppLifecycleListener(onHide: _onHide);
    _tuner.start();
  }

  Future<void> _open(Channel channel, bool Function() current) async {
    final request = await streamRequest(
      ref,
      title: channel.name,
      uri: (client) => client.liveStreamUri(channel.id),
    );
    // La résolution de l'adresse peut durer plus que l'attente du zapping :
    // une chaîne quittée entre-temps n'ouvre plus rien.
    if (!mounted || !current()) throw const PlaybackAbandoned();
    if (request == null) {
      _exit();
      throw const PlaybackAbandoned();
    }
    await _holds.open(_playback, request, opened: (ticket) => _ticket = ticket);
  }

  /// Sur mobile, passer l'app en arrière-plan arrête le flux tout de suite,
  /// puis quitte le lecteur (comme pour un film).
  void _onHide() {
    if (!_mobile || !mounted) return;
    // Plus de zapping ni de reconnexion en attente : rien ne rouvre le flux
    // en arrière-plan avant la fin de la fermeture.
    _tuner.stop();
    if (_ticket case final ticket?) unawaited(_holds.stop(_playback, ticket));
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route != null && route.isActive) {
      navigator.popUntil((r) => r == route);
      _exit();
    }
  }

  void _exit() => Navigator.maybePop(context);

  Future<void> _setFullscreen(bool on) async {
    setState(() => _fullscreen = on);
    await (on ? defaultEnterNativeFullscreen() : defaultExitNativeFullscreen());
  }

  void _toggleFullscreen() {
    if (!_mobile) unawaited(_setFullscreen(!_fullscreen));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _tuner.dispose();
    unawaited(_completed.cancel());
    unawaited(_audio.dispose());
    if (_ticket case final ticket?) unawaited(_holds.stop(_playback, ticket));
    if (_fullscreen) unawaited(defaultExitNativeFullscreen());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = ref.watch(phoneProvider);
    final television = ref.watch(televisionProvider);
    final view = Scaffold(
      key: const ValueKey('live.player'),
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: _tuner,
        builder: (context, _) {
          final error = _tuner.error;
          return Stack(
            fit: StackFit.expand,
            children: [
              PlayerVideo(playback: _playback, fill: _fill),
              if (error != null)
                // On zappe aussi depuis le message, et Échap quitte.
                // ↑ ↓ aussi : ses boutons sont côte à côte, et une
                // télécommande n'a souvent pas de touches CH.
                CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.channelUp): () =>
                        _tuner.zap(1),
                    const SingleActivator(LogicalKeyboardKey.channelDown): () =>
                        _tuner.zap(-1),
                    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                        _tuner.zap(1),
                    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                        _tuner.zap(-1),
                    const SingleActivator(LogicalKeyboardKey.escape): _exit,
                  },
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(color: Colors.white),
                    child: ErrorView(
                      key: const ValueKey('live.player.error'),
                      message: '${channelLabel(_tuner.channel)}\n\n$error',
                      onRetry: _tuner.retry,
                      onExit: _exit,
                    ),
                  ),
                )
              else ...[
                LiveControls(
                  tuner: _tuner,
                  player: _playback.player,
                  television: television,
                  fill: _fill,
                  onToggleFill: () => setState(() => _fill = !_fill),
                  fullscreen: _mobile ? null : _fullscreen,
                  onToggleFullscreen: _toggleFullscreen,
                  onExit: () => _fullscreen ? _setFullscreen(false) : _exit(),
                ),
                if (_tuner.opening)
                  const IgnorePointer(
                    child: Center(
                      child: CircularProgressIndicator(
                        key: ValueKey('live.player.opening'),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
    return PopScope<Channel>(
      canPop: false,
      // Toute sortie (retour, Échap, bouton) rend la chaîne affichée.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _tuner.channel);
      },
      child: _mobile ? MobileFullscreen(phone: phone, child: view) : view,
    );
  }
}

/// Ouvre le lecteur du direct sur [channel], zapping dans [channels] ; rend
/// la dernière chaîne affichée.
Future<Channel?> openLivePlayer(
  BuildContext context,
  Channel channel,
  List<Channel> channels,
) => Navigator.of(context).push<Channel>(
  MaterialPageRoute(
    builder: (_) => LivePlayerScreen(channel: channel, channels: channels),
  ),
);
