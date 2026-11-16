import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../downloads/downloads.dart';
import '../focus_ring.dart';
import '../library/library.dart';
import '../library/library_store.dart';
import 'catalog_index.dart';
import '../server/models.dart';
import 'versions.dart';

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
      title: entry.title,
      imageUrl: entry.poster,
      favorite: favorite,
      watched: watched,
      downloaded: downloaded,
      onTap: () => onOpen(entry),
    );
  }
}

/// Une affiche et son titre ; l'anneau autour de l'affiche quand elle a le
/// focus (clavier, télécommande).
class PosterTile extends StatelessWidget {
  const PosterTile({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.onTap,
    this.progress,
    this.onMenu,
    this.favorite = false,
    this.watched = false,
    this.downloaded = false,
  });

  final String title;
  final String? imageUrl;
  final VoidCallback onTap;

  /// Part regardée, en barre au bas de l'affiche.
  final double? progress;

  /// Appui long, clic droit, OK maintenu ou touche Menu : les actions
  /// secondaires.
  final VoidCallback? onMenu;

  /// Pastilles en haut à droite : dans « Ma liste », déjà vu, téléchargé
  /// (se lit sans réseau).
  final bool favorite;
  final bool watched;
  final bool downloaded;

  /// Place de l'anneau autour de l'affiche, vide sans focus.
  static final _border = focusRing.width;

  /// Marge autour du titre.
  static const _titleMargin = 8.0;

  /// Hauteur des cases de largeur [width] dont le plus haut titre est l'un
  /// de [titles] : pour une rangée paresseuse, qui ne mesure pas ses cases.
  /// Mêmes règles que le `Text` du titre (style, taille du texte, gras).
  static double heightFor(
    BuildContext context,
    double width,
    Iterable<String> titles,
  ) {
    var style = DefaultTextStyle.of(context).style
        .merge(Theme.of(context).textTheme.bodySmall);
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    var text = 0.0;
    for (final title in titles) {
      final painter = TextPainter(
        text: TextSpan(text: title, style: style),
        maxLines: 2,
        ellipsis: '…',
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        textHeightBehavior: DefaultTextHeightBehavior.maybeOf(context),
      )..layout(maxWidth: width - 2 * _titleMargin);
      if (painter.height > text) text = painter.height;
      painter.dispose();
    }
    return width * 3 / 2 + 2 * _titleMargin - _border + text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = this.progress;
    return _RemoteKeys(
      onTap: onTap,
      onMenu: onMenu,
      child: InkWell(
        onTap: onTap,
        onLongPress: onMenu,
        onSecondaryTap: onMenu,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: FocusRing(
                hug: true,
                child: Padding(
                  padding: EdgeInsets.all(_border),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child:
                        progress == null && !favorite && !watched && !downloaded
                        ? PosterImage(url: imageUrl, deferred: true)
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              PosterImage(url: imageUrl, deferred: true),
                              if (progress != null)
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: LinearProgressIndicator(
                                    value: progress,
                                  ),
                                ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Row(
                                  spacing: 4,
                                  children: [
                                    if (watched)
                                      const _Badge(Icons.check, 'Déjà vu'),
                                    if (favorite)
                                      const _Badge(
                                        Icons.favorite,
                                        'Dans ma liste',
                                      ),
                                    if (downloaded)
                                      const _Badge(
                                        Icons.download_done,
                                        'Téléchargé',
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            // Même écart entre l'image et le titre qu'entre le titre et le bas
            // de la case : la place de l'anneau compte déjà pour une part.
            Padding(
              padding: EdgeInsets.fromLTRB(
                _titleMargin,
                _titleMargin - _border,
                _titleMargin,
                _titleMargin,
              ),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Télécommande : OK maintenu ouvre le menu de la tuile (les répétitions de
/// la touche ne sont plus des clics), OK appuyé ouvre la fiche au relâchement,
/// la touche Menu ouvre le menu. Sans menu, OK reste un appui court et ses
/// répétitions sont ignorées.
class _RemoteKeys extends StatefulWidget {
  const _RemoteKeys({
    required this.onTap,
    required this.onMenu,
    required this.child,
  });

  final VoidCallback onTap;
  final VoidCallback? onMenu;
  final Widget child;

  @override
  State<_RemoteKeys> createState() => _RemoteKeysState();
}

class _RemoteKeysState extends State<_RemoteKeys> {
  /// OK enfoncé, ni relâché ni maintenu : la fiche s'ouvre au relâchement.
  var _pressed = false;

  static bool _isOk(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter;

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final onMenu = widget.onMenu;
    final key = event.logicalKey;
    if (onMenu != null &&
        key == LogicalKeyboardKey.contextMenu &&
        event is KeyDownEvent) {
      onMenu();
      return KeyEventResult.handled;
    }
    if (!_isOk(key)) return KeyEventResult.ignored;
    if (onMenu == null) {
      // Un appui court reste celui d'InkWell ; ses répétitions sont avalées.
      return event is KeyRepeatEvent
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    switch (event) {
      case KeyDownEvent():
        _pressed = true;
      case KeyRepeatEvent():
        // Maintenu : le menu s'ouvre sans attendre le relâchement. Son
        // dialogue avale la fin du maintien (voir `confirm`).
        if (_pressed) {
          _pressed = false;
          onMenu();
        }
      case KeyUpEvent():
        final press = _pressed;
        _pressed = false;
        if (press) widget.onTap();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _onKey,
    child: widget.child,
  );
}

/// Pastille ronde et sombre : lisible sur n'importe quelle affiche.
class _Badge extends StatelessWidget {
  const _Badge(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 14, color: Colors.white, semanticLabel: label),
      ),
    );
  }
}

/// Image réseau décodée à la taille affichée, avec une image de remplacement
/// si l'URL manque ou ne charge pas.
///
/// Avec [deferred], le chargement attend que l'image reste un instant à
/// l'écran : un défilement rapide (barre tirée d'un coup) ne lance pas le
/// téléchargement et le décodage de chaque affiche survolée. Une affiche déjà
/// vue s'affiche sans attendre.
///
/// `ponytail:` cache mémoire de Flutter seulement. `cached_network_image`
/// demande sqflite, absent sous Windows ; un cache disque viendra si le
/// rechargement des affiches devient gênant.
class PosterImage extends StatefulWidget {
  const PosterImage({
    super.key,
    required this.url,
    this.icon = Icons.movie,
    this.deferred = false,
  });

  final String? url;
  final IconData icon;
  final bool deferred;

  @override
  State<PosterImage> createState() => _PosterImageState();
}

class _PosterImageState extends State<PosterImage> {
  static const _delay = Duration(milliseconds: 150);

  // URL déjà affichées : pas d'attente en revenant sur une affiche.
  // ponytail: vidé au-delà de 4 000 entrées, un LRU si ça devient visible.
  static final _seen = <String>{};

  Timer? _timer;
  var _show = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(PosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final url = widget.url;
    _show = !widget.deferred || url == null || _seen.contains(url);
    if (!_show) {
      _timer = Timer(_delay, () => setState(() => _show = true));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(widget.icon, size: 40, color: colors.onSurfaceVariant),
      ),
    );
    if (url == null || !_show) return placeholder;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Arrondi par paliers de 128 px : redimensionner la fenêtre ne change
        // pas la clé du cache d'images à chaque pixel, donc ne retélécharge
        // pas les affiches (pas de cache disque).
        final width = constraints.maxWidth.isFinite
            ? ((constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)) /
                          128)
                      .ceil() *
                  128
            : null;
        return Image.network(
          url,
          fit: BoxFit.cover,
          cacheWidth: width,
          // Sans errorBuilder, une URL cassée écrirait une erreur en console.
          errorBuilder: (_, _, _) => placeholder,
          frameBuilder: (_, child, frame, synchronous) {
            if (!synchronous && frame == null) return placeholder;
            if (_seen.length > 4000) _seen.clear();
            _seen.add(url);
            return child;
          },
        );
      },
    );
  }
}
