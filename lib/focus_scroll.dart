import 'package:flutter/widgets.dart';

/// Durée du défilement quand le focus passe sur un élément hors écran ;
/// proche des 200 ms de `TvArrowKeys`.
const focusScrollDuration = Duration(milliseconds: 250);
const focusScrollCurve = Curves.easeOutCubic;

/// Comme la politique par défaut, mais le défilement vers l'élément qui prend
/// le focus est animé au lieu d'être instantané. Un nouveau focus relance
/// l'animation depuis la position courante.
void _smoothRequestFocus(
  FocusNode node, {
  ScrollPositionAlignmentPolicy? alignmentPolicy,
  double? alignment,
  Duration? duration,
  Curve? curve,
}) => FocusTraversalPolicy.defaultTraversalRequestFocusCallback(
  node,
  alignmentPolicy: alignmentPolicy,
  alignment: alignment,
  duration: duration ?? focusScrollDuration,
  curve: curve ?? focusScrollCurve,
);

/// À poser à la place de `FocusTraversalGroup` : même ordre de parcours
/// (lecture), défilement doux.
class SmoothFocusGroup extends StatelessWidget {
  const SmoothFocusGroup({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    policy: ReadingOrderTraversalPolicy(
      requestFocusCallback: _smoothRequestFocus,
    ),
    child: child,
  );
}
