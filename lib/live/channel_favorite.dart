import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../confirm.dart';
import '../library/library_store.dart';
import 'channel.dart';

/// Ajoute [channel] aux favorites, ou l'en retire ; vrai si elle y est
/// désormais.
bool toggleChannelFavorite(WidgetRef ref, Channel channel) {
  final library = ref.read(libraryProvider.notifier);
  if (ref.read(libraryProvider).isChannelFavorite(channel.id)) {
    library.removeChannelFavorite(channel.id);
    return false;
  }
  library.addChannelFavorite(
    id: channel.id,
    name: channel.name,
    number: channel.number,
    logo: channel.logo,
  );
  return true;
}

/// Une chaîne a vraiment démarré dans le lecteur : en tête des récentes.
void recordRecentChannel(WidgetRef ref, Channel channel) => ref
    .read(libraryProvider.notifier)
    .addRecentChannel(
      id: channel.id,
      name: channel.name,
      number: channel.number,
      logo: channel.logo,
    );

/// « Retirer des chaînes récentes ? », puis le retrait ; vrai si retirée.
Future<bool> removeRecentChannelWithConfirm(
  BuildContext context,
  WidgetRef ref,
  Channel channel,
) async {
  final library = ref.read(libraryProvider.notifier);
  final remove = await confirm(
    context,
    title: channel.name,
    content: 'Retirer des chaînes récentes ?',
    action: 'Retirer',
    focusCancel: true,
  );
  // Sans attendre l'écriture du fichier : la liste change tout de suite.
  if (remove) unawaited(library.removeRecentChannel(channel.id));
  return remove;
}

/// OK maintenu ou appui long sur une rangée : la favorite change, et un
/// message le dit (rien d'autre ne se voit de loin, sur une TV).
void toggleChannelFavoriteWithMessage(
  BuildContext context,
  WidgetRef ref,
  Channel channel,
) {
  final added = toggleChannelFavorite(ref, channel);
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          added
              ? '« ${channel.name} » ajoutée aux favorites'
              : '« ${channel.name} » retirée des favorites',
        ),
      ),
    );
}

/// Cœur « Ajouter aux favorites » / « Retirer des favorites » d'une chaîne.
/// [focusable] faux dans une rangée de liste : la télécommande passe d'une
/// chaîne à l'autre sans s'y arrêter (OK maintenu fait la même chose).
class ChannelFavoriteButton extends ConsumerWidget {
  const ChannelFavoriteButton({
    super.key,
    required this.channel,
    this.focusable = true,
    this.onPressed,
  });

  final Channel channel;
  final bool focusable;

  /// En plus du changement (le lecteur garde ses barres affichées).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorite = ref.watch(
      libraryProvider.select((l) => l.isChannelFavorite(channel.id)),
    );
    final button = IconButton(
      key: ValueKey('live.favorite.${channel.id}'),
      tooltip: favorite ? 'Retirer des favorites' : 'Ajouter aux favorites',
      icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
      onPressed: () {
        toggleChannelFavorite(ref, channel);
        onPressed?.call();
      },
    );
    return focusable ? button : ExcludeFocus(child: button);
  }
}
