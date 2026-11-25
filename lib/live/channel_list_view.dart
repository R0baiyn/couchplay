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
class ChannelList extends ConsumerWidget {
  const ChannelList({
    super.key,
    required this.categoryId,
    required this.onOpen,
    required this.onRefresh,
    this.header,
  });

  final String categoryId;
  final ValueChanged<Channel> onOpen;
  final RefreshCallback onRefresh;

  /// En-tête qui défile avec la liste (écran étroit).
  final Widget? header;

  /// Hauteur fixe d'une chaîne : certaines catégories en comptent des
  /// centaines. Laisse la place d'une seconde ligne sous le nom.
  static const _rowHeight = 72.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(liveCatalogProvider).value;
    final channels =
        ref.watch(liveChannelsProvider(categoryId)).value ?? const <Channel>[];
    return SmoothFocusGroup(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
          key: const ValueKey('live.list'),
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
                  itemExtent: _rowHeight,
                  itemCount: channels.length,
                  itemBuilder: (context, i) =>
                      _ChannelTile(channel: channels[i], onOpen: onOpen),
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
  const _ChannelTile({required this.channel, required this.onOpen});

  final Channel channel;
  final ValueChanged<Channel> onOpen;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('live.channel.${channel.id}'),
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
    onTap: () => onOpen(channel),
  );
}
