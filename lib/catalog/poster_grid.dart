import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../downloads/downloads.dart';
import '../library/library.dart';
import '../library/library_store.dart';
import 'catalog_index.dart';
import '../server/models.dart';
import '../poster_tile.dart';
import 'versions.dart';

export '../poster_image.dart';
export '../poster_tile.dart';

/// Grille d'affiches, en sliver : elle défile avec l'en-tête de l'écran.
///
/// Rangée par rangée plutôt qu'en grille à cases fixes : chaque rangée prend
/// la hauteur de ses titres (une ou deux lignes), sans réserver deux lignes
/// partout. Seules les rangées visibles sont construites, et chaque image est
/// décodée à la taille de sa case.
class SliverPosterGrid extends StatelessWidget {
  const SliverPosterGrid({
    super.key,
    required this.entries,
    required this.onOpen,
  });

  final List<CatalogEntry> entries;
  final ValueChanged<CatalogEntry> onOpen;

  static const maxTileWidth = 170.0;
  static const spacing = 12.0;

  /// Entre deux rangées, en plus de la marge sous chaque titre.
  static const rowSpacing = 8.0;

  /// Colonnes pour une largeur donnée : des cases de [maxTileWidth] au plus.
  static int columnsFor(double width) =>
      ((width + spacing) / (maxTileWidth + spacing)).ceil().clamp(1, 1000);

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.crossAxisExtent);
        final rows = (entries.length / columns).ceil();
        return SliverList.builder(
          itemCount: rows,
          itemBuilder: (context, row) => Padding(
            padding: const EdgeInsets.only(bottom: rowSpacing),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: spacing,
              children: [
                for (var column = 0; column < columns; column++)
                  Expanded(child: _tile(row * columns + column)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tile(int index) {
    // Dernière rangée incomplète : des cases vides gardent la même largeur.
    if (index >= entries.length) return const SizedBox.shrink();
    final entry = entries[index];
    return _EntryTile(
      // Un film et une série peuvent avoir le même id (grille des favoris).
      key: ValueKey((entry.kind, entry.item.id)),
      entry: entry,
      onOpen: onOpen,
    );
  }
}

/// Affiche d'une grille, marquée si l'une de ses versions est dans « Ma
/// liste » ou, pour un film, a été vue. Ne se reconstruit que si ces deux
/// marques changent, pas à chaque position enregistrée pendant la lecture.
///
/// Versions de l'index si possible : un film se répartit souvent entre
/// plusieurs catégories (« Films 4K », « FR · FILMS HD », son genre), et sa
/// fiche, qui les propose toutes, peut mettre en favori une version absente
/// de la catégorie affichée.
class _EntryTile extends ConsumerWidget {
  const _EntryTile({super.key, required this.entry, required this.onOpen});

  final CatalogEntry entry;
  final ValueChanged<CatalogEntry> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movie = entry.kind == ContentKind.movies;
    final versions =
        (movie
            ? ref.watch(
                catalogIndexProvider(ContentKind.movies).select(
                  (i) => i.value?.value.entryOf(entry.item.id)?.versions,
                ),
              )
            : null) ??
        entry.versions;
    final (favorite, watched) = ref.watch(
      libraryProvider.select(
        (library) => (
          versions.any((v) => library.favorites.containsKey(v.libraryKey)),
          movie &&
              versions.any(
                (v) => library.progress[v.libraryKey]?.watched ?? false,
              ),
        ),
      ),
    );
    // Une seule clé regardée : l'avancement d'un téléchargement ne
    // reconstruit aucune affiche.
    final downloaded = ref.watch(
      downloadedKeysProvider.select(
        (keys) =>
            keys.isNotEmpty && versions.any((v) => keys.contains(v.libraryKey)),
      ),
    );
    return PosterTile(
      key: ValueKey('catalog.poster.${entry.kind.name}-${entry.item.id}'),
      title: entry.title,
      imageUrl: entry.poster,
      favorite: favorite,
      watched: watched,
      downloaded: downloaded,
      onTap: () => onOpen(entry),
    );
  }
}
