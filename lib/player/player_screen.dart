import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../accounts/account_store.dart';
import '../accounts/server_session.dart';
import '../catalog/catalog_providers.dart';
import '../catalog/poster_grid.dart';
import '../library/library.dart';
import '../library/library_store.dart';
import '../server/models.dart';
import 'playback.dart';
import 'player_controls.dart';

/// Ouvre le lecteur sur un film ou un épisode du compte actif. Un contenu
/// commencé propose de reprendre ou de recommencer ; avec [resume], la
/// lecture reprend là sans rien demander (« Continuer à regarder »).
Future<void> openPlayer(
  BuildContext context,
  WidgetRef ref,
  PlayItem item, {
  Duration? resume,
}) async {
  // Un double clic sur « Lecture » ne doit pas empiler deux lecteurs.
  if (ModalRoute.of(context)?.isCurrent == false) return;
  var start = resume;
  if (start == null) {
    if (ref.read(libraryProvider).progress[item.key]?.resumeAt
        case final saved?) {
      start = await showDialog<Duration>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(item.title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, Duration.zero),
              child: const Text('Recommencer'),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, saved),
              child: Text('Reprendre à ${formatTime(saved)}'),
            ),
          ],
        ),
      );
      // Fermé sans choisir : on reste sur la fiche.
      if (start == null || !context.mounted) return;
    }
  }
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(item: item, startAt: start),
    ),
  );
}

/// Flux d'un contenu sur le compte actif, ou `null` sans compte.
PlayRequest? _requestFor(
  WidgetRef ref,
  PlayItem item, {
  String? audioLanguage,
  String? subtitleLanguage,
  Duration? start,
}) {
  final account = ref.read(activeAccountProvider);
  final client = ref.read(serverClientProvider);
  if (account == null || client == null) return null;
  return PlayRequest(
    title: item.title,
    url: client.streamUri(
      item.isEpisode ? ContentKind.series : ContentKind.movies,
      item.id,
      item.extension,
    ),
    userAgent: account.userAgent,
    secrets: [account.username, account.password],
    audioLanguage: audioLanguage,
    subtitleLanguage: subtitleLanguage,
    start: start,
  );
}

/// Lecture plein cadre. La position est enregistrée toutes les 10 s, à la
/// pause et à la sortie. Quitter l'écran arrête le flux.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.item, this.startAt});

  final PlayItem item;

  /// Position où démarrer, sinon le début.
  final Duration? startAt;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Playback _playback = ref.read(playbackProvider);

  /// Lu dans initState, pas à la première sauvegarde : `ref` n'est plus
  /// utilisable dans dispose, et une erreur là y sauterait l'arrêt du flux.
  late final LibraryNotifier _library;
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<bool>? _completed;
  StreamSubscription<bool>? _playing;
  Timer? _saveTimer;

  static const _saveEvery = Duration(seconds: 10);

  /// Ce qu'on regarde : change quand l'épisode suivant s'enchaîne.
  late PlayItem _item = widget.item;

  /// Langues des pistes choisies à la main, gardées pour l'épisode suivant
  /// (et pour « Réessayer »). Suivies au fil de la lecture : à la fin du
  /// fichier, media_kit remet la piste courante à « auto ».
  String? _audioLanguage;
  String? _subtitleLanguage;
  StreamSubscription<Track>? _track;

  /// Épisode suivant proposé à la fin de celui-ci, et son compte à rebours.
  ({PlayItem item, String? image})? _next;
  Timer? _countdown;
  var _secondsLeft = 0;
  static const _nextDelay = 10;
  final _playNowFocus = FocusNode();

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
    _library = ref.read(libraryProvider.notifier);
    if (_mobile) _setFullscreen(true);
    _lifecycle = AppLifecycleListener(onHide: _onHide);
    _completed = _playback.player.stream.completed.listen(_onCompleted);
    _playing = _playback.player.stream.playing.listen((playing) {
      if (!playing) _save();
    });
    _track = _playback.player.stream.track.listen((track) {
      if (track.audio.language case final language?) {
        _audioLanguage = language;
      }
      if (track.subtitle.id == 'no') {
        _subtitleLanguage = null;
      } else if (track.subtitle.language case final language?) {
        _subtitleLanguage = language;
      }
    });
    _saveTimer = Timer.periodic(_saveEvery, (_) {
      if (_playback.player.state.playing) _save();
    });
    if (widget.startAt case final start? when start > Duration.zero) {
      _resumeAt = start;
    }
    _open();
  }

  /// Enregistre où on en est, seulement sur un flux bien démarré : quitter
  /// pendant le chargement ou après un échec (position à 0) ne doit pas
  /// effacer la position enregistrée. À appeler avant tout arrêt du flux.
  void _save() {
    // Un autre lecteur a déjà pris le flux (écran en train de se fermer) :
    // sa position n'est pas la nôtre.
    if (_ticket != _playback.ticket) return;
    if (_opening || _error != null) return;
    final state = _playback.player.state;
    if (state.position <= Duration.zero) return;
    final item = _item;
    final position = state.position;
    final duration = state.duration;
    // Écrit juste après : appelé depuis dispose, modifier la bibliothèque
    // pendant le démontage de l'écran est interdit.
    scheduleMicrotask(
      () => unawaited(
        _library.saveProgress(item, position: position, duration: duration),
      ),
    );
  }

  /// Sur mobile, passer l'app en arrière-plan arrête le flux tout de suite
  /// (l'animation de sortie ne tourne pas en arrière-plan, donc on n'attend
  /// pas la fermeture de l'écran), puis quitte le lecteur, menu ouvert ou non.
  void _onHide() {
    if (!_mobile || !mounted) return;
    _save();
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
    if (!mounted) return;
    // Retour en arrière pendant le compte à rebours : on regarde encore.
    if (!completed) {
      if (_next != null) _cancelNext();
      return;
    }
    if (_opening) return;
    _save();
    if (cutShort) {
      _resumeAt = state.position;
      setState(
        () => _error =
            'La lecture s\'est interrompue : le serveur a coupé la connexion.',
      );
    } else if (_item.seriesId case final seriesId? when _next == null) {
      _offerNext(seriesId);
    }
  }

  /// Fin d'un épisode : propose le suivant, lancé seul après 10 s. Au
  /// dernier de la série, le lecteur se ferme. Si la fiche de la série n'a
  /// pas pu être chargée, le lecteur reste simplement sur la fin.
  void _offerNext(String seriesId) {
    final series = ref.read(seriesDetailsProvider(seriesId)).value;
    if (series == null) return;
    final next = nextEpisode(series, _item);
    if (next == null) {
      _exit();
      return;
    }
    setState(() {
      _next = next;
      _secondsLeft = _nextDelay;
    });
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft <= 1) {
        _playNext();
      } else {
        setState(() => _secondsLeft--);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _playNowFocus.requestFocus(),
    );
  }

  void _cancelNext() {
    _countdown?.cancel();
    setState(() => _next = null);
  }

  /// Enchaîne sur l'épisode suivant dans le même écran, avec les mêmes
  /// langues de pistes. `Playback.open` ferme le flux courant avant d'ouvrir
  /// le suivant : une seule connexion à la fois.
  void _playNext() {
    final next = _next;
    if (next == null) return;
    _countdown?.cancel();
    setState(() {
      _item = next.item;
      _next = null;
      _resumeAt = null;
    });
    _open();
  }

  /// Position où reprendre après une coupure.
  Duration? _resumeAt;

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    final request = _requestFor(
      ref,
      _item,
      audioLanguage: _audioLanguage,
      subtitleLanguage: _subtitleLanguage,
      start: _resumeAt,
    );
    if (request == null) {
      _exit();
      return;
    }
    final opening = _playback.open(request);
    _ticket = _playback.ticket;
    try {
      await opening;
      _resumeAt = null;
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
    _saveTimer?.cancel();
    _countdown?.cancel();
    _playNowFocus.dispose();
    unawaited(_completed?.cancel());
    unawaited(_playing?.cancel());
    unawaited(_track?.cancel());
    _save();
    unawaited(_playback.stop(_ticket));
    if (_fullscreen) unawaited(defaultExitNativeFullscreen());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    // Fiche de la série gardée chargée pendant un épisode, pour connaître le
    // suivant à la fin, même lancé depuis l'accueil.
    if (_item.seriesId case final seriesId?) {
      ref.watch(seriesDetailsProvider(seriesId));
    }
    final next = _next;
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
              title: _item.title,
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
            if (next != null)
              Align(
                alignment: Alignment.bottomRight,
                // Le focus est sur l'encart, hors des contrôles : Échap doit
                // quand même quitter (plein écran d'abord sur ordinateur).
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape): () =>
                        _fullscreen && !_mobile
                        ? _setFullscreen(false)
                        : _exit(),
                  },
                  child: _NextEpisodePanel(
                    title: next.item.title,
                    image: next.image ?? next.item.poster,
                    secondsLeft: _secondsLeft,
                    playNowFocus: _playNowFocus,
                    onPlayNow: _playNext,
                    onCancel: _cancelNext,
                  ),
                ),
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

/// « Épisode suivant dans 10 s », en bas à droite, par-dessus la fin.
class _NextEpisodePanel extends StatelessWidget {
  const _NextEpisodePanel({
    required this.title,
    required this.image,
    required this.secondsLeft,
    required this.playNowFocus,
    required this.onPlayNow,
    required this.onCancel,
  });

  final String title;
  final String? image;
  final int secondsLeft;
  final FocusNode playNowFocus;
  final VoidCallback onPlayNow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.deepPurple,
      ),
      child: Builder(
        builder: (context) {
          final text = Theme.of(context).textTheme;
          return Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    Text(
                      'Épisode suivant dans $secondsLeft s',
                      style: text.titleMedium,
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 12,
                      children: [
                        SizedBox(
                          width: 120,
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: PosterImage(url: image, icon: Icons.tv),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: onCancel,
                          child: const Text('Annuler'),
                        ),
                        FilledButton(
                          focusNode: playNowFocus,
                          onPressed: onPlayNow,
                          child: const Text('Lire maintenant'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
