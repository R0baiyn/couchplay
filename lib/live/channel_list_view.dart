import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../focus_ring.dart';
import '../focus_scroll.dart';
import '../poster_image.dart';
import '../server/status_views.dart';
import 'channel.dart';
import 'live_providers.dart';

/// Chaînes d'une catégorie, avec son éventuel en-tête repliable. La tirer vers
/// le bas l'actualise (toucher).
class ChannelList extends ConsumerStatefulWidget {
  const ChannelList({
    super.key,
    required this.categoryId,
    required this.onOpen,
    required this.onRefresh,
    this.header,
    this.focusId,
  });

  final String categoryId;

  /// Chaîne choisie, avec la liste affichée (pour le zapping).
  final void Function(Channel channel, List<Channel> channels) onOpen;
  final RefreshCallback onRefresh;

  /// En-tête qui défile avec la liste (écran étroit).
  final Widget? header;

  /// Chaîne à montrer et à remettre sous le focus (retour du lecteur) : à
  /// chaque nouvelle valeur.
  final String? focusId;

  /// Hauteur fixe d'une chaîne : certaines catégories en comptent des
  /// centaines. Laisse la place d'une seconde ligne sous le nom.
  static const _rowHeight = 72.0;

  @override
  ConsumerState<ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends ConsumerState<ChannelList> {
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'chaîne regardée');

  @override
  void didUpdateWidget(ChannelList old) {
    super.didUpdateWidget(old);
    if (widget.focusId case final id? when id != old.focusId) _reveal(id);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// La liste est paresseuse : la rangée de [id] n'existe peut-être pas
  /// encore. On défile jusqu'à elle, puis elle prend le focus.
  void _reveal(String id) {
    final channels = ref.read(liveChannelsProvider(widget.categoryId)).value;
    final index = channels?.indexWhere((c) => c.id == id) ?? -1;
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      _scroll.jumpTo(
        (index * ChannelList._rowHeight).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _focus.context;
        if (!mounted || context == null) return;
        _focus.requestFocus();
        Scrollable.ensureVisible(context);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(liveCatalogProvider).value;
    final channels =
        ref.watch(liveChannelsProvider(widget.categoryId)).value ??
        const <Channel>[];
    final header = widget.header;
    return SmoothFocusGroup(
      child: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: CustomScrollView(
          key: const ValueKey('live.list'),
          controller: _scroll,
          // Une catégorie courte ou vide se tire aussi.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            ?header,
            if (loaded != null && loaded.offline)
              SliverToBoxAdapter(
                child: OfflineBanner(
                  key: const ValueKey('live.offlineBanner'),
                  savedAt: loaded.savedAt,
                ),
              ),
            if (channels.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'Cette catégorie est vide.',
                    key: ValueKey('live.empty'),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                sliver: SliverFixedExtentList.builder(
                  itemExtent: ChannelList._rowHeight,
                  itemCount: channels.length,
                  itemBuilder: (context, i) => _ChannelTile(
                    channel: channels[i],
                    focusNode: channels[i].id == widget.focusId ? _focus : null,
                    onOpen: () => widget.onOpen(channels[i], channels),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Numéro, logo (ou icône de repli) et nom d'une chaîne.
class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.focusNode,
    required this.onOpen,
  });

  final Channel channel;
  final FocusNode? focusNode;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('live.channel.${channel.id}'),
    focusNode: focusNode,
    leading: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            '${channel.number ?? ''}',
            textAlign: TextAlign.end,
            maxLines: 1,
          ),
        ),
        SizedBox(
          width: 56,
          height: 40,
          child: PosterImage(
            url: channel.logo,
            icon: Icons.live_tv,
            fit: BoxFit.contain,
            deferred: true,
          ),
        ),
      ],
    ),
    title: FocusRing(
      child: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    // Le programme en cours et le suivant iront en `subtitle`.
    onTap: onOpen,
  );
}
