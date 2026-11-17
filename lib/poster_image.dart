import 'dart:async';

import 'package:flutter/material.dart';

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
