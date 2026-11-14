import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_providers.dart';
import '../catalog/catalog_screen.dart';
import '../catalog/poster_grid.dart';
import '../catalog/versions.dart';
import '../confirm.dart';
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
            _PosterRow(
              children: [
                for (final (:entry, :next) in started)
                  next != null
                      ? _tile(
                          key: ValueKey(next.key),
                          title: next.shortTitle,
                          imageUrl: next.poster,
                          onTap: () => openPlayer(context, ref, next),
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
            _LazyPosterRow(
              titles: [
                for (final favorite in favorites)
                  favorite.item.parsedName.display,
              ],
              itemBuilder: (context, i) {
                final favorite = favorites[i];
                return _tile(
                  key: ValueKey(favorite.key),
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

  /// Rangée « Vus » : les [_rowLength] plus récents ; l'écran Historique les
  /// a tous. Une affiche ouvre la fiche du film, ou celle de la série pour un
  /// épisode.
  Widget _seenRow(BuildContext context, List<Progress> entries) {
    final shown = entries.take(_rowLength).toList();
    return _LazyPosterRow(
      titles: [for (final entry in shown) entry.item.shortTitle],
      itemBuilder: (context, i) {
        final entry = shown[i];
        return _tile(
          key: ValueKey('seen:${entry.item.key}'),
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
      focusAction: true,
    );
    if (hide) await ref.read(libraryProvider.notifier).hide(entry);
  }
}

const _tileWidth = 130.0;

/// Affiches de la rangée « Vus » : elle reste courte.
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
class _PosterRow extends StatelessWidget {
  const _PosterRow({required this.children});

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
class _LazyPosterRow extends StatelessWidget {
  const _LazyPosterRow({required this.titles, required this.itemBuilder});

  final List<String> titles;
  final IndexedWidgetBuilder itemBuilder;

  static const _padding = 16.0;

  @override
  Widget build(BuildContext context) {
    final height = PosterTile.heightFor(context, _tileWidth, titles);
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
