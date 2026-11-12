import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// L'anneau de focus (décision D-006) : un contour blanc de 3 px, net sur
/// toutes les couleurs, autour de l'élément qui a le focus du clavier ou de
/// la télécommande. Jamais après un toucher.
const focusRing = BorderSide(color: Colors.white, width: 3);

/// [theme] avec l'anneau sur les boutons qui ont le focus.
///
/// L'état `focused` d'un bouton suit le focus, même après un toucher :
/// l'app ne pose ce thème qu'en mode clavier (voir `CouchPlayApp`). Pas les
/// puces : l'interpolation de leur thème perd une bordure qui dépend de
/// l'état ; elles prennent un [FocusRing].
ThemeData withFocusRing(ThemeData theme) {
  final style = ButtonStyle(
    side: WidgetStateBorderSide.resolveWith(
      (states) => states.contains(WidgetState.focused) ? focusRing : null,
    ),
  );
  return theme.copyWith(
    filledButtonTheme: FilledButtonThemeData(style: style),
    outlinedButtonTheme: OutlinedButtonThemeData(style: style),
    textButtonTheme: TextButtonThemeData(style: style),
    iconButtonTheme: IconButtonThemeData(style: style),
  );
}

/// L'anneau, pour un élément focusable que le thème ne couvre pas : placé
/// n'importe où à l'intérieur (titre d'une tuile, icône d'un onglet, texte
/// d'une entrée de menu), il entoure tout l'élément quand celui-ci a le
/// focus. Avec [hug], il entoure [child] seulement.
///
/// L'anneau est peint par-dessus, à l'intérieur des bords : rien ne bouge.
class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    required this.child,
    this.radius = 8,
    this.hug = false,
  });

  final Widget child;

  /// Rayon des coins, réduit à la demi-hauteur (pilule) au besoin.
  final double radius;

  final bool hug;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  FocusNode? _node;
  var _visible = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onModeChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final node = Focus.maybeOf(context);
    if (node == _node) return;
    _node?.removeListener(_update);
    _node = node?..addListener(_update);
    _update();
  }

  void _onModeChange(FocusHighlightMode _) => _update();

  void _update() {
    final visible =
        (_node?.hasPrimaryFocus ?? false) &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    if (visible != _visible) setState(() => _visible = visible);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onModeChange);
    _node?.removeListener(_update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Ring(
    target: !_visible || widget.hug ? null : _node,
    visible: _visible,
    radius: widget.radius,
    child: widget.child,
  );
}

class _Ring extends SingleChildRenderObjectWidget {
  const _Ring({
    required this.target,
    required this.visible,
    required this.radius,
    super.child,
  });

  final FocusNode? target;
  final bool visible;
  final double radius;

  @override
  _RenderRing createRenderObject(BuildContext context) =>
      _RenderRing(target, visible, radius);

  @override
  void updateRenderObject(BuildContext context, _RenderRing renderObject) {
    renderObject
      ..target = target
      ..visible = visible
      ..radius = radius;
  }
}

class _RenderRing extends RenderProxyBox {
  _RenderRing(this._target, this._visible, this._radius);

  FocusNode? _target;
  set target(FocusNode? value) {
    if (value == _target) return;
    _target = value;
    markNeedsPaint();
  }

  bool _visible;
  set visible(bool value) {
    if (value == _visible) return;
    _visible = value;
    markNeedsPaint();
  }

  double _radius;
  set radius(double value) {
    if (value == _radius) return;
    _radius = value;
    markNeedsPaint();
  }

  /// La zone de l'élément focusable dans le repère de ce widget, ou ce
  /// widget lui-même.
  Rect get _area {
    final box = _target?.context?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return Offset.zero & size;
    }
    return MatrixUtils.transformRect(
      box.getTransformTo(this),
      Offset.zero & box.size,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!_visible) return;
    final rect = _area.shift(offset).deflate(focusRing.width / 2);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        Radius.circular(min(_radius, rect.shortestSide / 2)),
      ),
      focusRing.toPaint(),
    );
  }
}
