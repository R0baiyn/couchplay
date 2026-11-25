import 'package:flutter/material.dart';

import '../poster_image.dart';
import 'channel.dart';

/// Numéro et nom d'une chaîne, sur une ligne.
String channelLabel(Channel channel) => switch (channel.number) {
  final number? => '$number · ${channel.name}',
  null => channel.name,
};

/// Logo, numéro et nom de la chaîne, en bas à gauche. Le programme en cours
/// et le suivant iront sous le nom.
class LiveBanner extends StatelessWidget {
  const LiveBanner({super.key, required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('live.player.banner'),
    padding: const EdgeInsets.all(24),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            SizedBox(
              width: 72,
              height: 48,
              child: PosterImage(
                url: channel.logo,
                icon: Icons.live_tv,
                fit: BoxFit.contain,
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                channelLabel(channel),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
