import 'package:flutter/material.dart';

import '../format.dart';
import 'live_providers.dart';

/// Programme en cours (titre et avancement) et le suivant (heure et titre),
/// sous le nom d'une chaîne : dans la liste et dans le bandeau du lecteur.
/// Dans un trou du guide, le suivant seul.
class OnAirView extends StatelessWidget {
  const OnAirView({super.key, required this.onAir});

  final OnAir onAir;

  @override
  Widget build(BuildContext context) {
    final current = onAir.current;
    final next = onAir.next;
    final color = DefaultTextStyle.of(context).style.color;
    return Column(
      key: const ValueKey('live.onAir'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (current != null)
              Flexible(
                child: Text(
                  current.title,
                  key: const ValueKey('live.onAir.current'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (next != null)
              Flexible(
                child: Padding(
                  padding: EdgeInsets.only(left: current == null ? 0 : 12),
                  child: Text(
                    '${formatClock(next.start)} ${next.title}',
                    key: const ValueKey('live.onAir.next'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color?.withValues(alpha: 0.7)),
                  ),
                ),
              ),
          ],
        ),
        if (current != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: LinearProgressIndicator(
              key: const ValueKey('live.onAir.progress'),
              value: onAir.progress,
              minHeight: 3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}
