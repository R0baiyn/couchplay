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

  /// Mise en page changée pendant qu'une autre route était au premier plan :
  /// `_restore` au retour.
  var _pending = false;

  String get _categoryId => widget.category.id;
  GuideLayout get _layout => ref.read(guideLayoutProvider(_categoryId));
  DateTime _now() => ref.read(guideNowProvider)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _goNow();
    });
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  /// « Maintenant » (et l'ouverture) : la case en cours de la ligne tenue.
  void _goNow() {
    _anchor = null;
    _restore(force: true);
  }

  bool get _onTop => ModalRoute.of(context)?.isCurrent ?? true;

  /// Seul point d'entrée qui replace la grille après un changement : depuis
  /// la ligne et l'heure tenues seulement, jamais depuis un ancien décalage
  /// en pixels (l'axe a pu repartir d'une autre heure). L'heure tenue sortie
  /// de l'axe (ou aucune) devient maintenant ; la case qui la couvre est mise
  /// au milieu de l'écran et prend le focus à l'image suivante, si le focus
  /// était dans la grille ou perdu, ou si [force].
  void _restore({bool force = false}) {
    final layout = _layout;
    if (layout.rowCount == 0 || !_horizontal.hasClients) return;
    _pending = false;
    final anchor = switch (_anchor) {
      final at? when layout.shows(at) => at,
      _ => _now(),
    };
    _anchor = anchor;
    final row = _row.clamp(0, layout.rowCount - 1);
    final slot = layout.slotAt(row, anchor);
    final x = layout
        .x(anchor)
        .clamp(layout.left(row, slot), layout.right(row, slot));
    final focused = FocusManager.instance.primaryFocus;
    _moveTo(
      row,
      slot,
      horizontal: x - _horizontal.position.viewportDimension / 2,
      animate: false,
      focus:
          force ||
          focused == null ||
          focused is FocusScopeNode ||
          focused.context == null ||
          _nodes.containsValue(focused),
    );
  }

  /// Nouvelle mise en page (guide relu, chaînes changées) : la grille est
  /// replacée à l'image suivante, ou au retour si une route la couvre.
  void _layoutChanged() {
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pending && _onTop) _restore();
    });
  }

  /// Focus sur la case [slot] de [row], la grille défilée pour la montrer
  /// (ou décalée de [horizontal]).
  void _moveTo(
    int row,
    int slot, {
    double? horizontal,
    bool keepAnchor = true,
    bool animate = true,
    bool focus = true,
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
    if (!focus) {
      h.jumpTo(dx);
      v.jumpTo(dy);
      return;
    }
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
      final watch = await showProgrammeDetail(context, channel, programme);
      if (!mounted) return;
      if (!watch) {
        // « Fermer » ou Retour : la grille telle quelle, sauf si le guide a
        // changé pendant le détail. Le focus est encore dans le détail qui se
        // ferme : on le reprend (la grille l'avait avant).
        if (_pending) _restore(force: true);
        return;
      }
    }
    final last = await openLivePlayer(context, channel, channels);
    if (!mounted) return;
    // Retour du lecteur : la dernière chaîne regardée, à l'heure qu'il est,
    // cherchée dans la liste d'à présent (les récentes se réordonnent).
    final shown = ref.read(liveChannelsProvider(_categoryId)).value;
    final index = last == null
        ? -1
        : shown?.indexWhere((c) => c.id == last.id) ?? -1;
    if (index >= 0) _row = index;
    _goNow();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(guideLayoutProvider(_categoryId), (_, _) => _layoutChanged());
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
