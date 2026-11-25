import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../poster_image.dart';
import 'channel.dart';
import 'live_providers.dart';
import 'on_air_view.dart';

/// Numéro et nom d'une chaîne, sur une ligne.
String channelLabel(Channel channel) => switch (channel.number) {
  final number? => '$number · ${channel.name}',
  null => channel.name,
};

/// Logo, numéro et nom de la chaîne, en bas à gauche ; dessous, le
/// programme en cours et le suivant si le guide les connaît.
class LiveBanner extends ConsumerWidget {
  const LiveBanner({super.key, required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onAir = switch (channel.epgChannelId) {
      final id? => ref.watch(onAirProvider(id)),
      null => null,
    };
    return Padding(
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(
                      channelLabel(channel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(color: Colors.white),
                    ),
                    if (onAir != null)
                      DefaultTextStyle.merge(
                        style: const TextStyle(color: Colors.white),
                        child: OnAirView(onAir: onAir),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
