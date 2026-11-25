import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/home_rows.dart';
import '../confirm.dart';
import '../library/library_store.dart';
import '../poster_tile.dart';
import 'live_banner.dart';
import 'live_player_screen.dart';
import 'live_providers.dart';

/// Rangée « Chaînes récentes » de l'accueil, la plus récente en premier.
/// Une chaîne ouvre le lecteur, zapping dans les récentes ; appui long, OK
/// maintenu ou touche Menu la retire. Rien sans chaîne récente.
///
/// Lue dans `library.json` seulement : l'accueil ne charge ni la liste des
/// chaînes ni le guide (plusieurs Mo) ; pas de « en cours » ici.
class RecentChannelsRow extends ConsumerWidget {
  const RecentChannelsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(libraryProvider.select((l) => l.recentChannels));
    if (recent.isEmpty) return const SizedBox.shrink();
    final channels = [for (final saved in recent) channelOf(saved)];
    return Column(
      key: const ValueKey('live.recentRow'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Text(
            'Chaînes récentes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        PosterRow(
          children: [
            for (final channel in channels)
              SizedBox(
                key: ValueKey('channel:${channel.id}'),
                width: tileWidth,
                child: PosterTile(
                  key: ValueKey('live.recentTile.${channel.id}'),
                  title: channelLabel(channel),
                  // Souvent en http, souvent absent : icône de télé à la
                  // place, logo en entier sinon.
                  imageUrl: channel.logo,
                  imageFit: BoxFit.contain,
                  imageIcon: Icons.live_tv,
                  onTap: () => openLivePlayer(context, channel, channels),
                  onMenu: () async {
                    final remove = await confirm(
                      context,
                      title: channel.name,
                      content: 'Retirer des chaînes récentes ?',
                      action: 'Retirer',
                      focusCancel: true,
                    );
                    if (remove) {
                      await ref
                          .read(libraryProvider.notifier)
                          .removeRecentChannel(channel.id);
                    }
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }
}
