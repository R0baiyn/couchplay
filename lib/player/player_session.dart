import 'dart:async';

import '../downloads/downloads.dart';
import '../library/library.dart';
import '../library/library_store.dart';
import 'playback.dart';

/// Ce que le lecteur écrit hors de l'écran : la position (toutes les 10 s, à
/// la pause et à la sortie) et l'arrêt du flux. Les dépendances sont lues
/// par l'écran dans `initState` : `ref` n'est plus utilisable dans `dispose`,
/// et une erreur là sauterait l'arrêt du flux.
class PlayerSession {
  PlayerSession({
    required this.playback,
    required this._library,
    required this._holds,
    required this._item,
    required this._ready,
  }) {
    _playing = playback.player.stream.playing.listen((playing) {
      if (!playing) save();
    });
    _timer = Timer.periodic(_saveEvery, (_) {
      if (playback.player.state.playing) save();
    });
  }

  static const _saveEvery = Duration(seconds: 10);

  final Playback playback;
  final LibraryNotifier _library;
  final DownloadHoldsNotifier _holds;
  final PlayItem Function() _item;

  /// Vrai quand ce flux est le nôtre et bien démarré.
  final bool Function() _ready;
  late final StreamSubscription<bool> _playing;
  late final Timer _timer;

  /// Enregistre où on en est, seulement sur un flux bien démarré : quitter
  /// pendant le chargement ou après un échec (position à 0) ne doit pas
  /// effacer la position enregistrée. À appeler avant tout arrêt du flux.
  void save() {
    if (!_ready()) return;
    final state = playback.player.state;
    if (state.position <= Duration.zero) return;
    final item = _item();
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

  /// Arrête notre flux, s'il l'est encore (pas déjà arrêté, pas remplacé
  /// par un autre lecteur). Une fois fermé, le téléchargement peut repartir
  /// (D-036), sauf si un autre lecteur a ouvert un flux entre-temps.
  Future<void> stopStream(int ticket) {
    if (ticket != playback.ticket) return Future.value();
    final holds = _holds;
    final stopping = playback.stop(ticket);
    // Lu juste après l'arrêt : une ouverture plus récente le change.
    final after = playback.ticket;
    return stopping.whenComplete(() {
      if (playback.ticket == after) holds.streaming = false;
    });
  }

  void dispose() {
    _timer.cancel();
    unawaited(_playing.cancel());
  }
}
