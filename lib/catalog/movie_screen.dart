import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/favorite_button.dart';
import '../library/library.dart';
import '../library/library_store.dart';
import '../player/player_screen.dart';
import '../search/search_index.dart';
import '../server/models.dart';
import 'catalog_providers.dart';
import 'details_view.dart';
import 'status_views.dart';
import 'versions.dart';

/// Fiche d'un film : ses versions s'il en a plusieurs, et « Lecture ».
///
/// Les versions viennent de l'index de recherche (toutes les catégories
/// visibles) ; tant qu'il charge, de l'affiche ouverte. Favori et
/// progression suivent la version choisie.
class MovieScreen extends ConsumerStatefulWidget {
  const MovieScreen({super.key, required this.entry});

  final CatalogEntry entry;

  @override
  ConsumerState<MovieScreen> createState() => _MovieScreenState();
}

class _MovieScreenState extends ConsumerState<MovieScreen> {
  /// Version choisie à la main ; sinon [preferredVersion].
  String? _chosenId;

  /// Dernière fiche affichée : gardée à l'écran pendant que celle d'une
  /// autre version charge, au lieu d'un écran vide.
  MovieDetails? _shown;

  @override
  Widget build(BuildContext context) {
    final id = widget.entry.item.id;
    final versions =
        (ref.watch(
                  searchIndexProvider.select(
                    (i) => i.value?.movies.entryOf(id),
                  ),
                ) ??
                widget.entry)
            .versions;
    final preferredId = ref.watch(
      libraryProvider.select((l) => preferredVersion(versions, l).id),
    );
    final selected =
        versions.where((v) => v.id == _chosenId).firstOrNull ??
        versions.firstWhere((v) => v.id == preferredId);

    final provider = movieDetailsProvider(selected.id);
    final details = ref.watch(provider);
    if (details.value case final value?) _shown = value;
    final shown = details.value ?? (details.isLoading ? _shown : null);

    return Scaffold(
      appBar: AppBar(
        title: Text(selected.parsedName.display),
        actions: [
          FavoriteButton(
            favoriteKey: 'movie:${selected.id}',
            otherKeys: [
              for (final v in versions)
                if (v != selected) 'movie:${v.id}',
            ],
            name: selected.name,
            poster: selected.poster,
          ),
        ],
      ),
      body: switch (details) {
        _ when shown != null => SingleChildScrollView(
          child: DetailsHeader(
            details: shown.details,
            action: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                if (versions.length > 1)
                  _VersionPicker(
                    versions: versions,
                    selected: selected,
                    onSelect: (id) => setState(() => _chosenId = id),
                  ),
                _PlayButton(
                  item: selected,
                  // Celle de la liste : la fiche affichée peut encore être
                  // celle d'une autre version.
                  extension: selected.extension ?? details.value?.extension,
                  poster: selected.poster ?? widget.entry.poster,
                ),
              ],
            ),
          ),
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(provider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// Une puce par version (« 4K MULTI », « HD VF »…), la choisie cochée.
class _VersionPicker extends StatelessWidget {
  const _VersionPicker({
    required this.versions,
    required this.selected,
    required this.onSelect,
  });

  final List<CatalogItem> versions;
  final CatalogItem selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final labels = versionLabels(versions);
    return FocusTraversalGroup(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (index, version) in versions.indexed)
            ChoiceChip(
              label: Text(labels[index]),
              selected: version.id == selected.id,
              onSelected: (_) => onSelect(version.id),
            ),
        ],
      ),
    );
  }
}

class _PlayButton extends ConsumerWidget {
  const _PlayButton({
    required this.item,
    required this.extension,
    required this.poster,
  });

  final CatalogItem item;
  final String? extension;
  final String? poster;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extension = this.extension;
    return FilledButton.icon(
      autofocus: true,
      icon: const Icon(Icons.play_arrow),
      label: Text(extension == null ? 'Fichier introuvable' : 'Lecture'),
      onPressed: extension == null
          ? null
          : () => openPlayer(
              context,
              ref,
              PlayItem.movie(
                id: item.id,
                extension: extension,
                name: item.name,
                poster: poster,
              ),
            ),
    );
  }
}
