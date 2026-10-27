import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_screen.dart';
import '../catalog/poster_grid.dart';
import '../player/player_screen.dart';
import '../settings/settings_screen.dart';
import 'favorites_screen.dart';
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
                  PosterTile(
                    key: ValueKey(entry.item.key),
                    title: entry.item.isEpisode
                        ? '${entry.item.name} · '
                              'S${entry.item.season}E${entry.item.episode}'
                        : entry.item.name,
                    imageUrl: entry.item.poster,
                    progress: entry.fraction,
                    // Reprend directement, sans passer par la fiche.
                    onTap: () => openPlayer(
                      context,
                      ref,
                      entry.item,
                      resume: entry.position,
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
                  PosterTile(
                    key: ValueKey(favorite.key),
                    title: favorite.name,
                    imageUrl: favorite.poster,
                    onTap: () => openDetails(context, favorite.item),
                  ),
              ],
            ),
        ],
      ),
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

/// Rangée d'affiches qui défile de côté : au doigt, à la souris (glisser),
/// à Shift + molette et aux flèches. Construite en entier : ces rangées
/// restent courtes.
class _PosterRow extends StatelessWidget {
  const _PosterRow({required this.children});

  final List<Widget> children;

  static const _tileWidth = 130.0;

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
          children: [
            for (final child in children)
              SizedBox(width: _tileWidth, child: child),
          ],
        ),
      ),
    );
  }
}
