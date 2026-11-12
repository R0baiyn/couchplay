import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_providers.dart';
import '../catalog/catalog_screen.dart';
import '../catalog/poster_grid.dart';
import '../catalog/versions.dart';
import '../player/player_screen.dart';
import '../settings/settings_screen.dart';
import 'favorites_screen.dart';
import 'history_screen.dart';
import 'library.dart';
import 'library_store.dart';

/// Premier onglet : « Continuer à regarder », puis « Ma liste », en rangées.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final started = library.continueWatching;
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
            _PosterRow(
              children: [
                for (final entry in started)
                  entry.finished
                      ? _UpNext(
                          key: ValueKey(entry.item.key),
                          finished: entry,
                          onMenu: () => _confirmHide(context, ref, entry),
                        )
                      : _tile(
                          key: ValueKey(entry.item.key),
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
                'Ma liste est vide.\n'
                'Le cœur d\'une fiche de film ou de série l\'y ajoute.',
              ),
            )
          else
            _PosterRow(
              children: [
                for (final favorite in favorites)
                  _tile(
                    key: ValueKey(favorite.key),
                    title: favorite.item.parsedName.display,
                    imageUrl: favorite.poster,
                    onTap: () =>
                        openDetails(context, CatalogEntry([favorite.item])),
                  ),
              ],
            ),
          if (seen.isNotEmpty) ...[
            header('Vus'),
            _entryRow(context, 'seen', seen),
          ],
          // Tout en bas, sous toutes les rangées : la liste complète.
          if (hasHistory)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
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

  /// Rangée d'une liste de progressions : les [_rowLength] plus récentes ;
  /// l'écran Historique les a toutes. Une affiche ouvre la fiche du film, ou
  /// celle de la série pour un épisode.
  Widget _entryRow(BuildContext context, String row, List<Progress> entries) =>
      _PosterRow(
        children: [
          for (final entry in entries.take(_rowLength))
            _tile(
              key: ValueKey('$row:${entry.item.key}'),
              title: entry.item.shortTitle,
              imageUrl: entry.item.poster,
              progress: entry.finished ? null : entry.fraction,
              onTap: () => openDetails(
                context,
                historyEntry(entry.item),
                episode: entry.item.isEpisode ? entry.item : null,
              ),
            ),
        ],
      );

  /// « Retirer » : l'entrée quitte la rangée, la progression reste.
  /// ponytail: appui long ou clic droit seulement ; une touche de menu de
  /// télécommande viendra avec l'étape TV.
  Future<void> _confirmHide(
    BuildContext context,
    WidgetRef ref,
    Progress entry,
  ) async {
    final hide = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.item.name),
        content: const Text('Retirer de « Continuer à regarder » ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (hide ?? false) await ref.read(libraryProvider.notifier).hide(entry);
  }
}

const _tileWidth = 130.0;

/// Affiches par rangée « Historique » et « Vus » : elles restent courtes.
const _rowLength = 20;

Widget _tile({
  required Key key,
  required String title,
  required String? imageUrl,
  required VoidCallback onTap,
  double? progress,
  VoidCallback? onMenu,
}) => SizedBox(
  key: key,
  width: _tileWidth,
  child: PosterTile(
    title: title,
    imageUrl: imageUrl,
    onTap: onTap,
    progress: progress,
    onMenu: onMenu,
  ),
);

/// Série dont l'épisode regardé en dernier est fini : l'épisode qui suit,
/// à lancer depuis le début. Rien tant que la fiche de la série n'est pas
/// chargée, ni à la fin de la série.
///
/// La fiche vient du cache du catalogue (un jour) : au plus une requête au
/// serveur par série et par jour, pas une à chaque lancement.
class _UpNext extends ConsumerWidget {
  const _UpNext({super.key, required this.finished, required this.onMenu});

  final Progress finished;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref
        .watch(cachedSeriesDetailsProvider(finished.item.seriesId!))
        .value;
    final next = series == null ? null : nextEpisode(series, finished.item);
    if (next == null) return const SizedBox.shrink();
    return _tile(
      key: ValueKey(next.item.key),
      title: next.item.shortTitle,
      imageUrl: next.item.poster,
      onTap: () => openPlayer(context, ref, next.item),
      onMenu: onMenu,
    );
  }
}

/// Rangée d'affiches qui défile de côté : au doigt, à la souris (glisser),
/// à Shift + molette et aux flèches. Construite en entier : ces rangées
/// restent courtes.
class _PosterRow extends StatelessWidget {
  const _PosterRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context)
          .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
      child: SingleChildScrollView(
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
