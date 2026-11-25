import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'guide_layout.dart';

/// Cases de la grille dans un seul viewport à deux axes du SDK : un seul
/// défilement horizontal pour toutes les lignes, et seules les cases en vue
/// (plus une marge) sont construites, aux places que dit [GuideLayout].
class GuideScrollView extends TwoDimensionalScrollView {
  const GuideScrollView({
    super.key,
    required this.layout,
    required super.delegate,
    super.verticalDetails,
    super.horizontalDetails,
  });

  final GuideLayout layout;

  @override
  Widget buildViewport(
    BuildContext context,
    ViewportOffset verticalOffset,
    ViewportOffset horizontalOffset,
  ) => _GuideViewport(
    layout: layout,
    verticalOffset: verticalOffset,
    verticalAxisDirection: verticalDetails.direction,
    horizontalOffset: horizontalOffset,
    horizontalAxisDirection: horizontalDetails.direction,
    delegate: delegate,
    mainAxis: mainAxis,
    clipBehavior: clipBehavior,
  );
}

class _GuideViewport extends TwoDimensionalViewport {
  const _GuideViewport({
    required this.layout,
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required super.delegate,
    required super.mainAxis,
    super.clipBehavior,
  });

  final GuideLayout layout;

  @override
  RenderTwoDimensionalViewport createRenderObject(BuildContext context) =>
      _RenderGuide(
        grid: layout,
        horizontalOffset: horizontalOffset,
        horizontalAxisDirection: horizontalAxisDirection,
        verticalOffset: verticalOffset,
        verticalAxisDirection: verticalAxisDirection,
        mainAxis: mainAxis,
        delegate: delegate,
        childManager: context as TwoDimensionalChildManager,
        clipBehavior: clipBehavior,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderGuide renderObject) {
    renderObject
      ..grid = layout
      ..horizontalOffset = horizontalOffset
      ..horizontalAxisDirection = horizontalAxisDirection
      ..verticalOffset = verticalOffset
      ..verticalAxisDirection = verticalAxisDirection
      ..mainAxis = mainAxis
      ..delegate = delegate
      ..clipBehavior = clipBehavior;
  }
}

/// Pose les cases que [GuideLayout] dit visibles (plus la marge de cache),
/// la case coupée au bord posée sur sa part visible.
class _RenderGuide extends RenderTwoDimensionalViewport {
  _RenderGuide({
    required this._grid,
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required super.delegate,
    required super.mainAxis,
    required super.childManager,
    super.clipBehavior,
  });

  /// Pas `layout` : le nom est pris par `RenderObject.layout`.
  GuideLayout _grid;
  set grid(GuideLayout value) {
    if (identical(value, _grid)) return;
    _grid = value;
    markNeedsLayout();
  }

  /// Marge construite autour de la vue, comme les listes du SDK : la case
  /// voisine existe déjà quand le focus y passe.
  static const _cache = RenderAbstractViewport.defaultCacheExtent;

  @override
  void layoutChildSequence() {
    final l = _grid;
    final width = viewportDimension.width;
    final height = viewportDimension.height;
    final dx = horizontalOffset.pixels;
    final dy = verticalOffset.pixels;
    final (:first, :end) = GuideLayout.visibleRows(
      max(0, dy - _cache),
      height + 2 * _cache,
      rowCount: l.rowCount,
    );
    for (var row = first; row < end; row++) {
      final range = l.visible(row, dx - _cache, dx + width + _cache);
      for (var i = range.first; i < range.end; i++) {
        final (left, right) = GuideLayout.clip(
          l.left(row, i),
          l.right(row, i),
          dx,
          dx + width,
        );
        final child = buildOrObtainChildFor(
          ChildVicinity(xIndex: i, yIndex: row),
        )!;
        child.layout(
          BoxConstraints.tight(Size(right - left, GuideLayout.rowHeight)),
        );
        parentDataOf(child).layoutOffset = Offset(
          left - dx,
          row * GuideLayout.rowHeight - dy,
        );
      }
    }
    verticalOffset.applyContentDimensions(0, max(0, l.height - height));
    horizontalOffset.applyContentDimensions(0, max(0, l.width - width));
  }
}
