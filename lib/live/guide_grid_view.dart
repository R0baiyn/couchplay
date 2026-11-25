import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../poster_image.dart';
import 'channel.dart';
import 'guide_layout.dart';
import 'guide_viewport_view.dart';
import 'live_providers.dart';

/// Grille des programmes : l'axe des heures en haut et les chaînes à gauche,
/// figés, autour des cases. Les cases défilent dans un seul viewport à deux
/// axes du SDK (un seul défilement horizontal pour toutes les lignes) et
/// seules celles en vue sont construites. L'axe et la colonne suivent les
/// deux contrôleurs.
class GuideGrid extends StatelessWidget {
  const GuideGrid({
    super.key,
    required this.layout,
    required this.channels,
    required this.vertical,
    required this.horizontal,
    required this.cell,
    required this.compact,
  });

  final GuideLayout layout;

  /// Une par ligne de [layout].
  final List<Channel> channels;
  final ScrollController vertical;
  final ScrollController horizontal;

  /// Case [slot] de la ligne [row].
  final Widget Function(int row, int slot) cell;

  /// Téléphone en portrait : colonne des chaînes réduite au logo.
  final bool compact;

  static const axisHeight = 32.0;

  static double columnWidth({required bool compact}) => compact ? 72 : 200;

  @override
  Widget build(BuildContext context) {
    final column = columnWidth(compact: compact);
    return Column(
      children: [
        SizedBox(
          height: axisHeight,
          child: Row(
            children: [
              SizedBox(width: column),
              Expanded(
                child: _TimeAxis(layout: layout, controller: horizontal),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: column,
                child: _ChannelColumn(
                  channels: channels,
                  controller: vertical,
                  compact: compact,
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    ScrollConfiguration(
                      // À la souris aussi, comme les rangées de l'Accueil.
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                      child: GuideScrollView(
                        key: const ValueKey('live.guide.grid'),
                        layout: layout,
                        verticalDetails: ScrollableDetails.vertical(
                          controller: vertical,
                        ),
                        horizontalDetails: ScrollableDetails.horizontal(
                          controller: horizontal,
                        ),
                        delegate: TwoDimensionalChildBuilderDelegate(
                          builder: (context, v) => cell(v.yIndex, v.xIndex),
                        ),
                      ),
                    ),
                    _NowLine(layout: layout, controller: horizontal),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

double _offset(ScrollController c) => c.hasClients ? c.offset : 0;

/// Repères de chaque demi-heure, posés selon le défilement horizontal.
class _TimeAxis extends StatelessWidget {
  const _TimeAxis({required this.layout, required this.controller});

  final GuideLayout layout;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: LayoutBuilder(
      builder: (context, constraints) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final offset = _offset(controller);
          return Stack(
            key: const ValueKey('live.guide.time'),
            children: [
              for (final t in layout.ticks(
                offset,
                offset + constraints.maxWidth,
              ))
                Positioned(
                  left: layout.x(t) - offset + 6,
                  top: 0,
                  bottom: 0,
                  child: Center(child: Text(formatClock(t))),
                ),
            ],
          );
        },
      ),
    ),
  );
}

/// Logo et nom des chaînes visibles, posés selon le défilement vertical.
class _ChannelColumn extends StatelessWidget {
  const _ChannelColumn({
    required this.channels,
    required this.controller,
    required this.compact,
  });

  final List<Channel> channels;
  final ScrollController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: LayoutBuilder(
      builder: (context, constraints) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final offset = _offset(controller);
          final (:first, :end) = GuideLayout.visibleRows(
            offset,
            constraints.maxHeight,
            rowCount: channels.length,
          );
          return Stack(
            children: [
              for (var row = first; row < end; row++)
                Positioned(
                  top: row * GuideLayout.rowHeight - offset,
                  left: 0,
                  right: 0,
                  height: GuideLayout.rowHeight,
                  child: _ChannelLabel(
                    key: ValueKey('live.guide.channel.${channels[row].id}'),
                    channel: channels[row],
                    compact: compact,
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _ChannelLabel extends StatelessWidget {
  const _ChannelLabel({
    super.key,
    required this.channel,
    required this.compact,
  });

  final Channel channel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final logo = SizedBox(
      width: 56,
      height: 40,
      child: PosterImage(
        url: channel.logo,
        icon: Icons.live_tv,
        fit: BoxFit.contain,
        deferred: true,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: compact
          ? Tooltip(
              message: channel.name,
              child: Center(child: logo),
            )
          : Row(
              spacing: 8,
              children: [
                logo,
                Expanded(
                  child: Text(
                    channel.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Trait « maintenant » : avance avec l'horloge du guide (une minuterie pour
/// toute l'app) et suit le défilement, sans rien reconstruire d'autre.
class _NowLine extends ConsumerWidget {
  const _NowLine({required this.layout, required this.controller});

  final GuideLayout layout;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final at = ref.watch(guideClockProvider);
    final color = Theme.of(context).colorScheme.primary;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (at.isBefore(layout.from) || !at.isBefore(layout.to)) {
          return const SizedBox.shrink();
        }
        return Positioned(
          key: const ValueKey('live.guide.nowLine'),
          left: layout.x(at) - _offset(controller) - 1,
          top: 0,
          bottom: 0,
          width: 2,
          child: IgnorePointer(child: ColoredBox(color: color)),
        );
      },
    );
  }
}
