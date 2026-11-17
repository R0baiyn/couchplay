import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'tech_info.dart';

/// Barres des contrôles : titre en haut, [bottom] en bas, chacune sur un
/// dégradé vers l'image. [onOver] dit si la souris est sur une barre (les
/// contrôles ne se masquent pas alors).
class PlayerBars extends StatelessWidget {
  const PlayerBars({
    super.key,
    required this.player,
    required this.title,
    required this.onExit,
    required this.onOver,
    required this.bottom,
  });

  final Player player;
  final String title;
  final VoidCallback onExit;
  final ValueChanged<bool> onOver;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    const shade = [Colors.black87, Colors.transparent];
    // Barre du haut ou du bas : dégradé vers l'image, marges du système de
    // son côté seulement.
    Widget bar(Widget child, {required bool top}) => MouseRegion(
      onEnter: (_) => onOver(true),
      onExit: (_) => onOver(false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: shade,
          ),
        ),
        child: SafeArea(top: top, bottom: !top, child: child),
      ),
    );
    return Column(
      children: [
        bar(
          top: true,
          Row(
            children: [
              IconButton(
                key: const ValueKey('player.back'),
                tooltip: 'Retour',
                icon: const Icon(Icons.arrow_back),
                onPressed: onExit,
              ),
              Expanded(
                child: Text(
                  title,
                  key: const ValueKey('player.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TechInfo(player: player),
            ],
          ),
        ),
        // Laisse passer clics et touchers vers les gestes de l'image.
        const Spacer(),
        bar(
          top: false,
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: bottom,
          ),
        ),
      ],
    );
  }
}
