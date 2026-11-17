import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'poster_grid.dart';
import '../downloads/downloads.dart';

const tileWidth = 130.0;

/// Affiches de la rangée « Vus » : elle reste courte.
const rowLength = 20;

/// [key] est aussi la clé du contenu (`movie:`, `episode:`, `series:`) :
/// pastille « téléchargé » si elle est prête.
Widget posterTile({
  required ValueKey<String> key,
  required ValueKey<String> tileKey,
  required String title,
  required String? imageUrl,
  required VoidCallback onTap,
  double? progress,
  VoidCallback? onMenu,
  String? downloadKey,
}) => SizedBox(
  key: key,
  width: tileWidth,
  child: Consumer(
    builder: (context, ref, _) => PosterTile(
      key: tileKey,
      title: title,
      imageUrl: imageUrl,
      onTap: onTap,
      progress: progress,
      onMenu: onMenu,
      downloaded: ref.watch(
        downloadedKeysProvider.select(
          (keys) => keys.contains(downloadKey ?? key.value),
        ),
      ),
    ),
  ),
);

/// Défilement de côté au doigt et à la souris (glisser), en plus de Shift +
/// molette et des flèches.
Widget _dragAnyDevice(BuildContext context, Widget child) =>
    ScrollConfiguration(
      behavior: ScrollConfiguration.of(context)
          .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
      child: child,
    );

/// Rangée d'affiches qui défile de côté. Construite en entier : « Continuer
/// à regarder » reste courte, et le titre de l'épisode suivant n'est connu
/// qu'une fois la fiche de la série chargée (pas de hauteur à l'avance).
class PosterRow extends StatelessWidget {
  const PosterRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _dragAnyDevice(
      context,
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: SliverPosterGrid.spacing,
          children: children,
        ),
      ),
    );
  }
}

/// Rangée d'affiches qui défile de côté, construite au fil du défilement :
/// « Ma liste » peut compter des centaines d'entrées, chacune une image à
/// télécharger et décoder. Sa hauteur, celle de son plus haut titre, est
/// calculée d'après [titles] (une case par titre, dans l'ordre).
class LazyPosterRow extends StatelessWidget {
  const LazyPosterRow({
    super.key,
    required this.titles,
    required this.itemBuilder,
  });

  final List<String> titles;
  final IndexedWidgetBuilder itemBuilder;

  static const _padding = 16.0;

  @override
  Widget build(BuildContext context) {
    final height = PosterTile.heightFor(context, tileWidth, titles);
    return SizedBox(
      height: height + 2 * _padding,
      child: _dragAnyDevice(
        context,
        ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(_padding),
          itemCount: titles.length,
          itemBuilder: itemBuilder,
          separatorBuilder: (_, _) =>
              const SizedBox(width: SliverPosterGrid.spacing),
        ),
      ),
    );
  }
}
