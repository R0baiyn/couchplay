import 'dart:async';

import 'package:flutter/widgets.dart';

import '../library/library.dart';

/// Épisode suivant proposé à la fin de celui-ci, et son compte à rebours.
/// Le nœud de focus est celui du bouton « Lancer maintenant » : créé et
/// libéré ici, avec le compte à rebours.
class NextUp {
  static const delay = 10;

  /// Proposé, ou `null` : rien n'est affiché.
  ({PlayItem item, String? image})? next;
  var secondsLeft = 0;
  final focus = FocusNode();
  Timer? _timer;

  /// Propose [next] ; [onTick] à chaque seconde, [onElapsed] à zéro.
  void offer(
    ({PlayItem item, String? image}) next, {
    required VoidCallback onTick,
    required VoidCallback onElapsed,
  }) {
    this.next = next;
    secondsLeft = delay;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (secondsLeft <= 1) {
        onElapsed();
      } else {
        secondsLeft--;
        onTick();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  /// Arrête le compte à rebours et retire la proposition.
  void cancel() {
    _timer?.cancel();
    next = null;
  }

  void dispose() {
    _timer?.cancel();
    focus.dispose();
  }
}
