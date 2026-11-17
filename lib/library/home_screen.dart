import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_providers.dart';
import '../catalog/catalog_screen.dart';
import '../catalog/versions.dart';
import '../confirm.dart';
import '../player/player_launch.dart';
import '../settings/settings_screen.dart';
import 'favorites_screen.dart';
import 'history_screen.dart';
import 'library.dart';
import 'home_rows.dart';
import 'library_store.dart';

/// Premier onglet : « Continuer à regarder », puis « Ma liste », en rangées.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    // Une série finie n'y est que si son épisode suivant est connu : sinon
    // l'en-tête resterait au-dessus d'une rangée vide.
    final started = [
      for (final entry in library.continueWatching)
        if (!entry.finished)
          (entry: entry, next: null)
        else if (_upNext(ref, entry) case final next?)
          (entry: entry, next: next),
    ];
    final favorites = library.favoritesByDate;
    final hasHistory = library.progress.isNotEmpty;
    final seen = library.seen;
    final theme = Theme.of(context);

    Widget header(String title, [Widget? action]) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
          ?action,
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accueil'),
        actions: const [SettingsButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (started.isNotEmpty) ...[
            header('Continuer à regarder'),
            PosterRow(
              children: [
                for (final (:entry, :next) in started)
                  next != null
                      ? posterTile(
                          key: ValueKey(next.key),
                          tileKey: ValueKey('library.continueTile.${next.key}'),
                          title: next.shortTitle,
                          imageUrl: next.poster,
                          onTap: () => openPlayer(context, ref, next),
                          onMenu: () => _confirmHide(context, ref, entry),
                        )
                      : posterTile(
                          key: ValueKey(entry.item.key),
                          tileKey: ValueKey(
                            'library.continueTile.${entry.item.key}',
                          ),
                          title: entry.item.shortTitle,
                          imageUrl: entry.item.poster,
                          progress: entry.fraction,
                          // Reprend directement, sans passer par la fiche.
                          onTap: () => openPlayer(
                            context,
                            ref,
                            entry.item,
                            // À peine commencé : depuis le début.
                            resume: entry.resumeAt ?? Duration.zero,
                          ),
                          onMenu: () => _confirmHide(context, ref, entry),
                        ),
              ],
            ),
          ],
          header(
            'Ma liste',
            favorites.isEmpty
                ? null
                : TextButton(
                    key: const ValueKey('library.favoritesAll'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const FavoritesScreen(),
                      ),
                    ),
                    child: const Text('Tout voir'),
                  ),
          ),
          if (favorites.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                key: ValueKey('library.favoritesEmpty'),
                'Ma liste est vide.\n'
                'Le cœur d\'une fiche de film ou de série l\'y ajoute.',
              ),
            )
          else
            LazyPosterRow(
              titles: [
                for (final favorite in favorites)
                  favorite.item.parsedName.display,
              ],
              itemBuilder: (context, i) {
                final favorite = favorites[i];
                return posterTile(
                  key: ValueKey(favorite.key),
                  tileKey: ValueKey('library.favoriteTile.${favorite.key}'),
                  title: favorite.item.parsedName.display,
                  imageUrl: favorite.poster,
                  onTap: () =>
                      openDetails(context, CatalogEntry([favorite.item])),
                );
              },
            ),
          if (seen.isNotEmpty) ...[header('Vus'), _seenRow(context, seen)],
          // Tout en bas, sous toutes les rangées : la liste complète.
          if (hasHistory)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('library.historyButton'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const HistoryScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.history),
                  label: const Text('Historique'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Rangée « Vus » : les [rowLength] plus récents ; l'écran Historique les
  /// a tous. Une affiche ouvre la fiche du film, ou celle de la série pour un
  /// épisode.
  Widget _seenRow(BuildContext context, List<Progress> entries) {
    final shown = entries.take(rowLength).toList();
    return LazyPosterRow(
      titles: [for (final entry in shown) entry.item.shortTitle],
      itemBuilder: (context, i) {
        final entry = shown[i];
        return posterTile(
          key: ValueKey('seen:${entry.item.key}'),
          tileKey: ValueKey('library.seenTile.${entry.item.key}'),
          downloadKey: entry.item.key,
          title: entry.item.shortTitle,
          imageUrl: entry.item.poster,
          progress: entry.finished ? null : entry.fraction,
          onTap: () => openDetails(
            context,
            CatalogEntry([entry.item.catalogItem]),
            episode: entry.item.isEpisode ? entry.item : null,
          ),
        );
      },
    );
  }

  /// « Retirer » : l'entrée quitte la rangée, la progression reste.
  /// ponytail: appui long ou clic droit seulement ; une touche de menu de
  /// télécommande viendra avec l'étape TV.
  Future<void> _confirmHide(
    BuildContext context,
    WidgetRef ref,
    Progress entry,
  ) async {
    final hide = await confirm(
      context,
      title: entry.item.name,
      content: 'Retirer de « Continuer à regarder » ?',
      action: 'Retirer',
      focusCancel: true,
    );
    if (hide) await ref.read(libraryProvider.notifier).hide(entry);
  }
}

/// Série dont l'épisode regardé en dernier ([finished]) est fini : l'épisode
/// qui suit, à lancer depuis le début. `null` tant que la fiche de la série
/// n'est pas chargée, et à la fin de la série.
///
/// La fiche vient du cache du catalogue (un jour) : au plus une requête au
/// serveur par série et par jour, pas une à chaque lancement.
PlayItem? _upNext(WidgetRef ref, Progress finished) {
  final series = ref
      .watch(cachedSeriesDetailsProvider(finished.item.seriesId!))
      .value;
  return series == null ? null : nextEpisode(series, finished.item)?.item;
}
