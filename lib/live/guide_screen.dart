import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../focus_scroll.dart';
import '../server/models.dart';
import '../television.dart';
import 'channel.dart';
import 'guide_cell_view.dart';
import 'guide_grid_view.dart';
import 'guide_layout.dart';
import 'live_player_screen.dart';
import 'live_providers.dart';

/// Ouvre la grille des programmes des chaînes de [category].
Future<void> openGuide(BuildContext context, Category category) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => GuideScreen(category: category)));

/// Grille des programmes d'une catégorie, ouverte sur « maintenant ».
///
/// À la télécommande, ← → passent au programme voisin de la même chaîne,
/// ↑ ↓ à la chaîne voisine en gardant l'heure ([_anchor]) ; la grille défile
/// pour suivre. Le focus est tenu par la ligne et la case, pas par un nœud :
/// la case visée peut ne pas être construite encore.
class GuideScreen extends ConsumerStatefulWidget {
  const GuideScreen({super.key, required this.category});

  final Category category;

  @override
  ConsumerState<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends ConsumerState<GuideScreen> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  /// Nœud de focus de chaque case construite, par (ligne, case).
  final _nodes = <(int, int), FocusNode>{};

  var _row = 0;
  var _slot = 0;

  /// Heure que ↑ ↓ gardent ; posée à l'ouverture, par « Maintenant » et par
  /// ← →, jamais par ↑ ↓ (sinon le focus glisserait de ligne en ligne).
  DateTime? _anchor;

  /// Heure que `_refocus` va mettre au milieu de l'écran, à l'image suivante.
  DateTime? _shown;

  String get _categoryId => widget.category.id;
  GuideLayout get _layout => ref.read(guideLayoutProvider(_categoryId));
  DateTime _now() => ref.read(guideNowProvider)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _goNow(animate: false);
    });
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  /// « Maintenant » : la case en cours de la ligne tenue, l'heure au milieu.
  void _goNow({bool animate = true}) {
    final layout = _layout;
    if (layout.rowCount == 0 || !_horizontal.hasClients) return;
    final now = _now();
    _anchor = now;
    final row = _row.clamp(0, layout.rowCount - 1);
    final extent = _horizontal.position.viewportDimension;
    _moveTo(
      row,
      layout.slotAt(row, now),
      horizontal: layout.x(now) - extent / 2,
      animate: animate,
    );
  }

  /// Focus sur la case [slot] de [row], la grille défilée pour la montrer
  /// (ou décalée de [horizontal]).
  void _moveTo(
    int row,
    int slot, {
    double? horizontal,
    bool keepAnchor = true,
    bool animate = true,
  }) {
    final layout = _layout;
    final h = _horizontal.position;
    final v = _vertical.position;
    final dx =
        (horizontal ??
                GuideLayout.reveal(
                  h.pixels,
                  h.viewportDimension,
                  layout.left(row, slot),
                  layout.right(row, slot),
                ))
            .clamp(h.minScrollExtent, h.maxScrollExtent);
    final dy = GuideLayout.reveal(
      v.pixels,
      v.viewportDimension,
      row * GuideLayout.rowHeight,
      (row + 1) * GuideLayout.rowHeight,
    ).clamp(v.minScrollExtent, v.maxScrollExtent);
    if (!keepAnchor) _anchor = layout.anchorOf(row, slot, dx);
    _row = row;
    _slot = slot;
    final node = _nodes[(row, slot)];
    if (animate && node != null) {
      node.requestFocus();
      for (final (position, to) in [(h, dx), (v, dy)]) {
        if (position.pixels != to) {
          position.animateTo(
            to,
            duration: focusScrollDuration,
            curve: focusScrollCurve,
          );
        }
      }
      return;
    }
    // La case n'est pas construite : on y saute, elle prend le focus à
    // l'image suivante.
    h.jumpTo(dx);
    v.jumpTo(dy);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes[(_row, _slot)]?.requestFocus();
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final direction = arrowDirection(event);
    if (direction == null) return KeyEventResult.ignored;
    if (!(_nodes[(_row, _slot)]?.hasPrimaryFocus ?? false)) {
      return KeyEventResult.ignored;
    }
    final layout = _layout;
    // Au bord, la touche passe : ↑ sur la 1re chaîne va aux boutons.
    switch (direction) {
      case TraversalDirection.left || TraversalDirection.right:
        final step = direction == TraversalDirection.left ? -1 : 1;
        final slot = layout.neighbour(_row, _slot, step);
        if (slot == null) return KeyEventResult.ignored;
        _moveTo(_row, slot, keepAnchor: false);
      case TraversalDirection.up || TraversalDirection.down:
        final step = direction == TraversalDirection.up ? -1 : 1;
        final row = layout.neighbourRow(_row, step);
        if (row == null) return KeyEventResult.ignored;
        _moveTo(row, layout.slotAt(row, _anchor ?? _now()));
    }
    return KeyEventResult.handled;
  }

  /// Guide rechargé ou chaînes changées, écran ouvert : l'axe a pu
  /// repartir d'une autre heure (rechargement des 24 h). On garde à l'écran
  /// l'heure qui y était, ou maintenant si elle n'est plus sur l'axe ; l'heure
  /// tenue passe aussi à maintenant si elle en est sortie. La même ligne
  /// reprend le focus, sur la case de cette heure.
  void _refocus(GuideLayout? previous, GuideLayout layout) {
    if (layout.rowCount == 0 || !_horizontal.hasClients) return;
    final now = _now();
    final h = _horizontal.position;
    // Deux recalculs de suite (chargement, puis guide lu) : le second part
    // de l'heure visée par le premier, pas encore appliquée à l'écran.
    final center =
        _shown ?? previous?.timeAt(h.pixels + h.viewportDimension / 2);
    final shown = center != null && layout.shows(center) ? center : now;
    _shown = shown;
    if (!(_anchor != null && layout.shows(_anchor!))) _anchor = now;
    _row = _row.clamp(0, layout.rowCount - 1);
    _slot = layout.slotAt(_row, _anchor!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shown = null;
      // Lecteur ou détail par-dessus : au retour, `_open` replace la grille.
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      final dx = layout.x(shown) - h.viewportDimension / 2;
      final focused = FocusManager.instance.primaryFocus;
      // Le focus n'est repris que s'il était dans la grille (ou perdu).
      if (focused == null ||
          focused is FocusScopeNode ||
          focused.context == null ||
          _nodes.containsValue(focused)) {
        _moveTo(_row, _slot, horizontal: dx, animate: false);
      } else {
        h.jumpTo(dx.clamp(h.minScrollExtent, h.maxScrollExtent));
      }
    });
  }

  /// Toucher ou OK : la chaîne si le programme passe (ou rien d'annoncé),
  /// sinon son détail.
  Future<void> _open(int row, int slot, List<Channel> channels) async {
    final layout = _layout;
    if (row >= channels.length || slot >= layout.slots(row).length) return;
    _row = row;
    _slot = slot;
    final channel = channels[row];
    final s = layout.slots(row)[slot];
    final programme = s.programme;
    if (programme != null && !s.playsAt(_now())) {
      if (!await showProgrammeDetail(context, channel, programme)) return;
      if (!mounted) return;
    }
    final last = await openLivePlayer(context, channel, channels);
    // Retour du lecteur : la dernière chaîne regardée, à l'heure qu'il est.
    final index = last == null
        ? -1
        : channels.indexWhere((c) => c.id == last.id);
    if (index < 0 || !mounted) return;
    _row = index;
    _goNow(animate: false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(guideLayoutProvider(_categoryId), _refocus);
    final layout = ref.watch(guideLayoutProvider(_categoryId));
    final channels =
        ref.watch(liveChannelsProvider(_categoryId)).value ?? const <Channel>[];
    return Scaffold(
      key: const ValueKey('live.guide'),
      appBar: AppBar(
        title: Text('Guide · ${widget.category.name}'),
        actions: [
          TextButton.icon(
            key: const ValueKey('live.guide.now'),
            onPressed: _goNow,
            icon: const Icon(Icons.schedule),
            label: const Text('Maintenant'),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: GuideGrid(
            layout: layout,
            channels: channels,
            vertical: _vertical,
            horizontal: _horizontal,
            compact: constraints.maxWidth < railMinWidth,
            cell: (row, slot) {
              final s = layout.slots(row)[slot];
              return GuideCell(
                key: ValueKey(
                  'live.guide.${channels[row].id}.'
                  '${s.start.millisecondsSinceEpoch ~/ 1000}',
                ),
                slot: s,
                vicinity: (row, slot),
                nodes: _nodes,
                onFocused: () {
                  if ((row, slot) == (_row, _slot)) return;
                  // Focus venu d'ailleurs (toucher, Tab) : son heure.
                  _row = row;
                  _slot = slot;
                  _anchor = layout.anchorOf(row, slot, _horizontal.offset);
                },
                onOpen: () => _open(row, slot, channels),
              );
            },
          ),
        ),
      ),
    );
  }
}
