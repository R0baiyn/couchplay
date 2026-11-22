import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../downloads/downloads.dart';
import '../library/library.dart';
import '../library/library_store.dart';
import '../server/models.dart';
import '../television.dart';
import 'playback.dart';
import 'player_next_up.dart';
import 'player_request.dart';
import 'player_session.dart';
import 'player_track_memory.dart';
import 'player_view.dart';

export 'player_request.dart' show endedEarly, localRequest;

/// Lecture plein cadre. La position est enregistrée toutes les 10 s, à la
/// pause et à la sortie. Quitter l'écran arrête le flux.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.item,
    required this.seriesDetails,
    this.startAt,
  });

  final PlayItem item;

  /// Fiche d'une série, pour proposer l'épisode suivant : fournie par le
  /// catalogue, qui la charge (le lecteur est sous lui, D-050).
  final FutureProvider<SeriesDetails> Function(String seriesId) seriesDetails;

  /// Position où démarrer, sinon le début.
  final Duration? startAt;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Playback _playback = ref.read(playbackProvider);

  /// Lus dans initState : `ref` n'est plus utilisable dans dispose.
  late final DownloadsNotifier _downloads;
  late final DownloadHoldsNotifier _holds;
  late final PlayerSession _session;
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<bool>? _completed;

  /// Ce qu'on regarde : change quand l'épisode suivant s'enchaîne.
  late PlayItem _item = widget.item;

  /// Pistes choisies à la main, gardées pour l'épisode suivant et « Réessayer ».
  late final TrackMemory _tracks = TrackMemory(_playback.player);
  final _nextUp = NextUp();

  /// Position où reprendre après une coupure.
  Duration? _resumeAt;

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
    _downloads = ref.read(downloadsProvider.notifier);
    _holds = ref.read(downloadHoldsProvider.notifier);
    _downloads.playerOpened();
    if (_mobile) _setFullscreen(true);
    _lifecycle = AppLifecycleListener(onHide: _onHide);
    _completed = _playback.player.stream.completed.listen(_onCompleted);
    _session = PlayerSession(
      playback: _playback,
      library: ref.read(libraryProvider.notifier),
      holds: _holds,
      item: () => _item,
      // Pas pendant le chargement ni après un échec ; pas si un autre
      // lecteur a déjà pris le flux (sa position n'est pas la nôtre).
      ready: () => _ticket == _playback.ticket && !_opening && _error == null,
    );
    final start = widget.startAt;
    if (start != null && start > Duration.zero) _resumeAt = start;
    _open();
  }

  /// Sur mobile, passer l'app en arrière-plan arrête le flux tout de suite
  /// (l'animation de sortie ne tourne pas en arrière-plan, donc on n'attend
  /// pas la fermeture de l'écran), puis quitte le lecteur, menu ouvert ou non.
  void _onHide() {
    if (!_mobile || !mounted) return;
    _session.save();
    // Sans ticket, rien n'a été ouvert ici : le flux en cours n'est pas le nôtre.
    if (_ticket case final ticket?) unawaited(_session.stopStream(ticket));
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
    final cutShort = endedEarly(state.position, state.duration);
    if (!mounted) return;
    // Retour en arrière pendant le compte à rebours : on regarde encore.
    if (!completed) {
      if (_nextUp.next != null) _cancelNext();
      return;
    }
    if (_opening) return;
    _session.save();
    if (cutShort) {
      _resumeAt = state.position;
      setState(
        () => _error =
            'La lecture s\'est interrompue : le serveur a coupé la connexion.',
      );
    } else if (_item.seriesId case final seriesId? when _nextUp.next == null) {
      _offerNext(seriesId);
    }
  }

  /// Fin d'un épisode : propose le suivant, lancé seul après 10 s. Au
  /// dernier de la série, le lecteur se ferme. Sans fiche de la série (hors
  /// ligne), le suivant vient des téléchargements ; s'il n'y en a pas, le
  /// lecteur reste simplement sur la fin.
  void _offerNext(String seriesId) {
    final series = ref.read(widget.seriesDetails(seriesId)).value;
    final next = nextUpFor(
      series,
      ref.read(downloadsProvider).entries.values,
      _item,
    );
    if (next == null) {
      if (series != null) _exit();
      return;
    }
    setState(() {
      _nextUp.offer(next, onTick: () => setState(() {}), onElapsed: _playNext);
    });
  }

  void _cancelNext() => setState(_nextUp.cancel);

  /// Enchaîne sur l'épisode suivant dans le même écran, avec les mêmes
  /// langues de pistes. `Playback.open` ferme le flux courant avant d'ouvrir
  /// le suivant : une seule connexion à la fois.
  void _playNext() {
    final next = _nextUp.next;
    if (next == null) return;
    setState(() {
      _nextUp.cancel();
      _item = next.item;
      _resumeAt = null;
    });
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    final item = _item;
    final audioLanguage = _tracks.audioLanguage;
    final subtitleLanguage = _tracks.subtitleLanguage;
    final start = _resumeAt;
    int? ticket;
    // Une ouverture remplacée (écran fermé, épisode suivant lancé) ne touche
    // plus à l'écran ni au flux : ils ne sont plus les siens.
    bool current() => mounted && ticket == _ticket;
    try {
      final source = await openContent(
        file: _downloads.fileOf(item),
        local: (file) => localRequest(
          item,
          file,
          audioLanguage: audioLanguage,
          subtitleLanguage: subtitleLanguage,
          start: start,
        ),
        stream: () async {
          final request = await requestFor(
            ref,
            item,
            audioLanguage: audioLanguage,
            subtitleLanguage: subtitleLanguage,
            start: start,
          );
          // Écran fermé pendant la résolution : rien à ouvrir.
          if (!mounted) throw const PlaybackAbandoned();
          return request;
        },
        open: (request) {
          final opening = _playback.open(request);
          ticket = _ticket = _playback.ticket;
          return opening;
        },
        dropFile: () => _downloads.remove(item.key),
        // Avant l'ouverture d'un flux, le ticket n'est pas encore connu.
        streaming: (open) {
          if (open ? mounted : current()) _holds.streaming = open;
        },
        downloading: () => _downloads.downloading,
        pauseDownloads: () => _holds.pauseAll(DownloadHold.playback),
      );
      if (source == null) {
        if (mounted) _exit();
        return;
      }
      _resumeAt = null;
      if (current()) _tracks.matchByTitle();
    } on PlaybackAbandoned {
      return;
    } on NameNotResolved {
      if (mounted && (ticket == null || current())) {
        setState(
          () => _error =
              'Serveur introuvable : Cloudflare ne connaît pas son nom.',
        );
      }
    } on PlaybackFailed catch (e) {
      if (current()) setState(() => _error = e.message);
    } finally {
      if (mounted && (ticket == null || current())) {
        setState(() => _opening = false);
      }
    }
  }

  Future<void> _setFullscreen(bool on) async {
    setState(() => _fullscreen = on);
    await (on ? defaultEnterNativeFullscreen() : defaultExitNativeFullscreen());
  }

  void _exit() => Navigator.maybePop(context);

  /// Échap hors des contrôles : quitte d'abord le plein écran sur
  /// ordinateur, comme dans les contrôles, puis le lecteur.
  void _back() => _fullscreen && !_mobile ? _setFullscreen(false) : _exit();

  @override
  void dispose() {
    _lifecycle.dispose();
    _session.dispose();
    _nextUp.dispose();
    unawaited(_completed?.cancel());
    _tracks.dispose();
    _session.save();
    final ticket = _ticket;
    final stopped = ticket == null
        ? Future<void>.value()
        : _session.stopStream(ticket);
    // Fichier fermé : une vidéo vue peut être effacée.
    unawaited(stopped.whenComplete(_downloads.playerClosed));
    if (_fullscreen) unawaited(defaultExitNativeFullscreen());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fiche de la série gardée chargée pendant un épisode, pour connaître le
    // suivant à la fin, même lancé depuis l'accueil.
    if (_item.seriesId case final seriesId?) {
      ref.watch(widget.seriesDetails(seriesId));
    }
    return PlayerView(
      playback: _playback,
      title: _item.title,
      fill: _fill,
      // Sur mobile, toujours en plein écran : pas de bouton.
      fullscreen: _mobile ? null : _fullscreen,
      volume: !ref.watch(televisionProvider),
      opening: _opening,
      error: _error,
      next: _nextUp.next,
      secondsLeft: _nextUp.secondsLeft,
      playNowFocus: _nextUp.focus,
      onToggleFill: () => setState(() => _fill = !_fill),
      onToggleFullscreen: () {
        if (!_mobile) _setFullscreen(!_fullscreen);
      },
      onExit: _exit,
      onBack: _back,
      onRetry: _open,
      onPlayNext: _playNext,
      onCancelNext: _cancelNext,
    );
  }
}
