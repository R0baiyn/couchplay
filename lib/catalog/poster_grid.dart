import 'dart:async';

import 'package:flutter/material.dart';

import '../server/models.dart';

/// Grille d'affiches, en sliver : elle défile avec l'en-tête de l'écran.
///
/// Rangée par rangée plutôt qu'en grille à cases fixes : chaque rangée prend
/// la hauteur de ses titres (une ou deux lignes), sans réserver deux lignes
/// partout. Seules les rangées visibles sont construites, et chaque image est
/// décodée à la taille de sa case.
class SliverPosterGrid extends StatelessWidget {
  const SliverPosterGrid({
    super.key,
    required this.items,
    required this.onOpen,
  });

  final List<CatalogItem> items;
  final ValueChanged<CatalogItem> onOpen;

  static const maxTileWidth = 170.0;
  static const spacing = 12.0;
  static const rowSpacing = 16.0;

  /// Colonnes pour une largeur donnée : des cases de [maxTileWidth] au plus.
  static int columnsFor(double width) =>
      ((width + spacing) / (maxTileWidth + spacing)).ceil().clamp(1, 1000);

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.crossAxisExtent);
        final rows = (items.length / columns).ceil();
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
    if (index >= items.length) return const SizedBox.shrink();
    final item = items[index];
    return PosterTile(
      // Un film et une série peuvent avoir le même id (grille des favoris).
      key: ValueKey((item.kind, item.id)),
      title: item.name,
      imageUrl: item.poster,
      onTap: () => onOpen(item),
    );
  }
}

/// Une affiche et son titre ; un cadre net quand elle a le focus (clavier,
/// télécommande).
class PosterTile extends StatefulWidget {
  const PosterTile({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.onTap,
  });

  final String title;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  State<PosterTile> createState() => _PosterTileState();
}

class _PosterTileState extends State<PosterTile> {
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: widget.onTap,
      onFocusChange: (focused) => setState(() => _focused = focused),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _focused
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  width: 3,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: PosterImage(url: widget.imageUrl, deferred: true),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
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
