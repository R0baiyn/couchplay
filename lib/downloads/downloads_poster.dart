import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../poster_image.dart';
import '../library/library.dart';
import 'downloads.dart';

/// Vignette 2:3 d'un contenu téléchargé : l'affiche enregistrée à côté de
/// la vidéo (la page s'ouvre hors ligne), sinon celle du serveur, sinon
/// l'icône. Pour un épisode, l'affiche de sa série.
class DownloadPoster extends ConsumerWidget {
  const DownloadPoster(this.item, {super.key, this.width = 48});

  final PlayItem item;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Relue à chaque nouvelle liste : l'affiche arrive après la ligne.
    ref.watch(downloadsProvider.select((s) => s.entries));
    final file = ref.read(downloadsProvider.notifier).posterOf(item);
    final network = PosterImage(
      url: item.poster,
      icon: item.isEpisode ? Icons.tv : Icons.movie,
    );
    final image = file == null
        ? network
        : Image.file(
            file,
            fit: BoxFit.cover,
            cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).ceil(),
            // Fichier abîmé : le serveur, puis l'icône.
            errorBuilder: (_, _, _) => network,
          );
    return SizedBox(
      width: width,
      height: width * 3 / 2,
      child: ClipRRect(borderRadius: BorderRadius.circular(4), child: image),
    );
  }
}
