import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logging.dart';
import '../player/playback.dart';
import '../player/player_request.dart';
import 'channel.dart';

/// Chaîne regardée, zapping et reconnexion du lecteur du direct, sans
/// widget ni minuterie dans l'écran (D-087) :
/// - zapping dans [channels] (la liste d'où l'on vient), en boucle, en
///   aperçu ([previewing]) : la chaîne affichée change tout de suite, celle
///   en cours continue de jouer ; la chaîne affichée ne s'ouvre qu'après
///   [zapDelay] sans nouvel appui (dix appuis rapides = une ouverture), ou
///   tout de suite par [confirm] ; revenir sur la chaîne en cours finit
///   l'aperçu sans rien ouvrir ;
/// - flux coupé ([lost]) : une seule reconnexion, après 1 s, puis
///   [lostMessage]. Le droit à une reconnexion ne revient qu'avec un zapping
///   ou [retry] : un flux coupé toutes les 15 s ne boucle pas ; coupé
///   pendant l'aperçu : pas de reconnexion, la chaîne affichée s'ouvrira à la
///   fin de l'attente (même si c'est celle qui s'est coupée) ;
/// - refus du serveur : son message, sans autre essai que ceux de
///   `Playback.open` (comme un film) ; pendant l'aperçu, aucun message.
final class LiveTuner extends ChangeNotifier {
  LiveTuner({
    required List<Channel> channels,
    required Channel start,
    required this._open,
    this._onWatched,
  }) {
    final index = channels.indexWhere((c) => c.id == start.id);
    _channels = index < 0 ? [start] : channels;
    _index = index < 0 ? 0 : index;
  }

  /// Attente sans nouvel appui avant d'ouvrir la chaîne choisie : de quoi
  /// parcourir les chaînes au bandeau sans ouvrir chacune (D-090).
  static const zapDelay = Duration(seconds: 2);

  /// Durée d'affichage du bandeau de la chaîne.
  static const bannerFor = Duration(seconds: 4);

  /// Attente avant la reconnexion d'un flux coupé.
  static const reconnectDelay = Duration(seconds: 1);

  static const lostMessage =
      'La chaîne s\'est coupée : le réseau a lâché, ou un autre appareil '
      'utilise peut-être ton abonnement.';

  /// Ouvre le flux de la chaîne. Après chaque attente (adresse à résoudre),
  /// `current()` faux : un zapping ou un arrêt est passé, ne rien ouvrir
  /// (lever `PlaybackAbandoned`).
  final Future<void> Function(Channel channel, bool Function() current) _open;
  final void Function(Channel)? _onWatched;
  late final List<Channel> _channels;
  late int _index;

  /// Chaîne dont le flux est ouvert (ou en cours d'ouverture), `null` après
  /// un échec : y revenir le rouvre.
  Channel? _tuned;
  var _generation = 0;
  var _reconnected = false;
  var _stopped = false;
  Timer? _zap;
  Timer? _reconnect;

  /// Bandeau de la chaîne : montré à l'ouverture et à chaque zapping.
  final banner = AutoHide(bannerFor);

  /// Chaîne affichée (bandeau) : celle choisie, même avant l'ouverture de
  /// son flux.
  Channel get channel => _channels[_index];

  /// Flux en cours d'ouverture, ou reconnexion attendue.
  bool get opening => _opening;
  var _opening = false;

  /// Message à montrer à la place de l'image, avec « Réessayer ».
  String? get error => _error;
  String? _error;

  /// Aperçu : la chaîne affichée n'est pas celle qui joue, elle s'ouvrira à
  /// la fin de l'attente.
  bool get previewing => _zap?.isActive ?? false;

  /// Ouvre la chaîne de départ.
  void start() {
    banner.show();
    unawaited(_tune());
  }

  /// Chaîne suivante ([step] = 1) ou précédente (−1).
  void zap(int step) {
    if (_channels.length < 2) return;
    _index = (_index + step) % _channels.length;
    _zap?.cancel();
    // De retour sur la chaîne qui joue : l'aperçu finit, rien à ouvrir. Une
    // reconnexion attendue n'a pas de chaîne qui joue (`_tuned` nul).
    if (!_playing) {
      _reconnect?.cancel();
      // Le message est celui d'une autre chaîne que la chaîne affichée.
      _error = null;
      _zap = Timer(zapDelay, _tuneChoice);
    }
    banner.show();
    notifyListeners();
  }

  /// Pendant l'aperçu (OK, toucher du bandeau) : ouvre tout de suite la
  /// chaîne affichée. Faux hors de l'aperçu : rien n'est fait.
  bool confirm() {
    if (!previewing) return false;
    _tuneChoice();
    return true;
  }

  /// La chaîne affichée est celle dont le flux est ouvert (ou s'ouvre).
  bool get _playing => identical(_tuned, channel) && _error == null;

  /// Ouvre la chaîne choisie au zapping : nouvelle chaîne, nouveau droit à
  /// une reconnexion.
  void _tuneChoice() {
    _reconnected = false;
    unawaited(_tune());
  }

  /// Après un message : rouvre la chaîne affichée.
  void retry() {
    _reconnected = false;
    _tuned = null;
    unawaited(_tune());
  }

  /// Le flux en cours s'est terminé (un direct ne finit pas : il a été
  /// coupé). Ignoré pendant une ouverture, une attente ou après un message.
  void lost() {
    if (_stopped || _opening || _error != null || _tuned == null) return;
    _tuned = null;
    if (previewing) {
      log(
        'Direct : flux coupé pendant l\'aperçu, ouverture à la fin de '
        'l\'attente',
      );
      return;
    }
    if (_reconnected) {
      log('Direct : flux coupé de nouveau, pas d\'autre reconnexion');
      _setError(lostMessage);
      return;
    }
    _reconnected = true;
    log('Direct : flux coupé, reconnexion dans ${reconnectDelay.inSeconds} s');
    _opening = true;
    _reconnect = Timer(reconnectDelay, () => unawaited(_tune()));
    notifyListeners();
  }

  Future<void> _tune() async {
    _zap?.cancel();
    _reconnect?.cancel();
    final channel = this.channel;
    if (_stopped || _playing) return;
    final generation = ++_generation;
    _tuned = channel;
    _opening = true;
    _error = null;
    notifyListeners();
    bool current() => generation == _generation && !_stopped;
    try {
      await _open(channel, current);
      if (!current()) return;
      _opening = false;
      notifyListeners();
      _onWatched?.call(channel);
    } on PlaybackAbandoned {
      // Remplacée (zapping, arrêt) : rien à dire. Encore la nôtre (lecteur
      // pris par un autre écran) : pas de roue sans fin.
      if (!current()) return;
      _failed(const PlaybackFailed().message);
    } on Exception catch (e) {
      if (!current()) return;
      _failed(switch (e) {
        PlaybackFailed() => e.message,
        NameNotResolved() => e.message,
        _ => const PlaybackFailed().message,
      });
    }
  }

  /// La chaîne en cours n'a pas pu s'ouvrir. Pendant l'aperçu, pas de
  /// message (il porterait le nom de la chaîne affichée) : celle-ci s'ouvre
  /// à la fin de l'attente.
  void _failed(String message) {
    _tuned = null;
    if (!previewing) return _setError(message);
    _opening = false;
    notifyListeners();
  }

  void _setError(String message) {
    _opening = false;
    _error = message;
    notifyListeners();
  }

  /// Arrête tout : attentes annulées, ouverture en cours ignorée, plus rien
  /// ne s'ouvre.
  void stop() {
    _stopped = true;
    _generation++;
    _zap?.cancel();
    _reconnect?.cancel();
  }

  @override
  void dispose() {
    stop();
    banner.dispose();
    super.dispose();
  }
}

/// Affiché pendant [after] après chaque [show] ; tant que [hold] est vrai
/// (souris sur les barres), le masquage attend.
final class AutoHide extends ChangeNotifier {
  AutoHide(this.after);

  final Duration after;
  Timer? _timer;

  bool get visible => _visible;
  var _visible = false;

  bool hold = false;

  /// Affiche et relance le compte à rebours.
  void show() {
    _timer?.cancel();
    _timer = Timer(after, _expired);
    if (_visible) return;
    _visible = true;
    notifyListeners();
  }

  void hide() {
    _timer?.cancel();
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }

  void _expired() => hold ? show() : hide();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
