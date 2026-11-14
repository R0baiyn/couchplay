import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// L'app tourne sur une TV (Android TV, Google TV) : la télécommande y est
/// la seule saisie, et le clavier à l'écran couvre la moitié de l'image.
/// Fourni par `main()`.
final televisionProvider = Provider<bool>((ref) => false);

/// Demandé à Android (`MainActivity.kt`) au démarrage.
Future<bool> isTelevision() async {
  if (!Platform.isAndroid) return false;
  const channel = MethodChannel('couchplay/device');
  return await channel.invokeMethod<bool>('isTelevision') ?? false;
}

/// Sens d'un appui (ou d'une répétition) de flèche ; `null` pour une autre
/// touche ou un relâchement.
TraversalDirection? arrowDirection(KeyEvent event) => event is KeyUpEvent
    ? null
    : switch (event.logicalKey) {
        LogicalKeyboardKey.arrowUp => TraversalDirection.up,
        LogicalKeyboardKey.arrowDown => TraversalDirection.down,
        LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
        LogicalKeyboardKey.arrowRight => TraversalDirection.right,
        _ => null,
      };

/// Sur TV, ↑ ↓ sans rien à atteindre dans ce sens font défiler la page :
/// le résumé d'une fiche, sous le dernier bouton, se lit à la télécommande.
/// Placé au-dessus des écrans, il passe après leurs propres touches (lecteur,
/// curseurs).
class TvArrowKeys extends ConsumerWidget {
  const TvArrowKeys({super.key, required this.child});

  final Widget child;

  /// Part de la hauteur visible parcourue à chaque appui.
  static const _page = 0.8;

  static KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final direction = arrowDirection(event);
    final down = direction == TraversalDirection.down;
    if (!down && direction != TraversalDirection.up) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null) return KeyEventResult.ignored;
    if (focused.focusInDirection(direction!)) {
      return KeyEventResult.handled;
    }
    final context = focused.context;
    final position = context == null
        ? null
        : Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (position != null) {
      final step = position.viewportDimension * _page;
      position.animateTo(
        (position.pixels + (down ? step : -step)).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(televisionProvider)) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: child,
    );
  }
}
