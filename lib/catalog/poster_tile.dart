import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../focus_ring.dart';
import 'poster_image.dart';

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
                                      const _Badge(
                                        Icons.check,
                                        'Déjà vu',
                                        key: ValueKey('catalog.badgeWatched'),
                                      ),
                                    if (favorite)
                                      const _Badge(
                                        Icons.favorite,
                                        'Dans ma liste',
                                        key: ValueKey('catalog.badgeFavorite'),
                                      ),
                                    if (downloaded)
                                      const _Badge(
                                        Icons.download_done,
                                        'Téléchargé',
                                        key: ValueKey(
                                          'catalog.badgeDownloaded',
                                        ),
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
  const _Badge(this.icon, this.label, {super.key});

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
