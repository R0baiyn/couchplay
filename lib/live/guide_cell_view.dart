import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../focus_ring.dart';
import '../format.dart';
import 'channel.dart';
import 'guide.dart';
import 'guide_layout.dart';
import 'live_providers.dart';

/// Une case de la grille : titre et heures du programme, mis en avant
/// pendant qu'il passe ; « Pas de programme » dans un trou du guide. Son nœud
/// de focus est inscrit dans [nodes] tant qu'elle est construite.
class GuideCell extends ConsumerStatefulWidget {
  const GuideCell({
    super.key,
    required this.slot,
    required this.vicinity,
    required this.nodes,
    required this.onOpen,
    required this.onFocused,
  });

  final GuideSlot slot;

  /// Ligne et case : où la grille la cherche pour lui donner le focus.
  final (int, int) vicinity;
  final Map<(int, int), FocusNode> nodes;
  final VoidCallback onOpen;
  final VoidCallback onFocused;

  @override
  ConsumerState<GuideCell> createState() => _GuideCellState();
}

class _GuideCellState extends ConsumerState<GuideCell> {
  final _focus = FocusNode(debugLabel: 'case du guide');

  @override
  void initState() {
    super.initState();
    widget.nodes[widget.vicinity] = _focus;
  }

  @override
  void didUpdateWidget(GuideCell old) {
    super.didUpdateWidget(old);
    if (old.vicinity == widget.vicinity) return;
    _unregister(old.vicinity);
    widget.nodes[widget.vicinity] = _focus;
  }

  /// Une case plus récente a pu prendre la place.
  void _unregister((int, int) vicinity) {
    if (identical(widget.nodes[vicinity], _focus)) {
      widget.nodes.remove(vicinity);
    }
  }

  @override
  void dispose() {
    _unregister(widget.vicinity);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final programme = slot.programme;
    final onAir =
        programme != null && ref.watch(guideClockProvider.select(slot.playsAt));
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(
      fontSize: 12,
      color: scheme.onSurface.withValues(alpha: 0.7),
    );
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Material(
        color: switch ((programme, onAir)) {
          (null, _) => scheme.surfaceContainerLow,
          (_, true) => scheme.primaryContainer,
          _ => scheme.surfaceContainerHigh,
        },
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          focusNode: _focus,
          borderRadius: BorderRadius.circular(6),
          onTap: widget.onOpen,
          onFocusChange: (focused) {
            if (focused) widget.onFocused();
          },
          child: FocusRing(
            radius: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    programme?.title ?? 'Pas de programme',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: programme == null ? muted : null,
                  ),
                  if (programme != null)
                    Text(
                      _hours(programme),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: muted,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _hours(Programme p) =>
    '${formatClock(p.start)} – ${formatClock(p.stop)}';

/// Détail d'un programme passé ou à venir ; vrai si « Regarder la chaîne ».
Future<bool> showProgrammeDetail(
  BuildContext context,
  Channel channel,
  Programme programme,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('live.guide.detail'),
        title: Text(programme.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text(
                '${channel.name} · ${formatDate(programme.start)} · '
                '${_hours(programme)}',
              ),
              if (programme.description case final text?) Text(text),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Fermer'),
          ),
          FilledButton(
            key: const ValueKey('live.guide.watch'),
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Regarder la chaîne'),
          ),
        ],
      ),
    ) ??
    false;
