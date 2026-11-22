import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../library/library.dart';
import 'tech_info.dart';

/// Titre du lecteur pour [item] : sur téléphone, un épisode en deux parties,
/// la série puis « S1E5 · titre » ([PlayerTitle] les met sur une ligne si
/// elles tiennent) ; sinon une seule.
(String, String?) playerTitle(PlayItem item, {required bool phone}) =>
    phone && item.isEpisode
    ? (
        item.name,
        'S${item.season}E${item.episode}'
            '${item.episodeTitle == null ? '' : ' · ${item.episodeTitle}'}',
      )
    : (item.title, null);

/// Barres des contrôles : titre en haut, [bottom] en bas, chacune sur un
/// dégradé vers l'image. [onOver] dit si la souris est sur une barre (les
/// contrôles ne se masquent pas alors).
class PlayerBars extends StatelessWidget {
  const PlayerBars({
    super.key,
    required this.player,
    required this.title,
    this.subtitle,
    required this.onExit,
    required this.onOver,
    required this.bottom,
  });

  final Player player;
  final String title;

  /// Seconde partie du titre (voir [playerTitle]).
  final String? subtitle;
  final VoidCallback onExit;
  final ValueChanged<bool> onOver;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    const shade = [Colors.black87, Colors.transparent];
    // Barre du haut ou du bas : dégradé vers l'image, marges du système de
    // son côté seulement.
    Widget bar(Widget child, {required bool top}) => MouseRegion(
      onEnter: (_) => onOver(true),
      onExit: (_) => onOver(false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: shade,
          ),
        ),
        child: SafeArea(top: top, bottom: !top, child: child),
      ),
    );
    return Column(
      children: [
        bar(
          top: true,
          Row(
            children: [
              IconButton(
                key: const ValueKey('player.back'),
                tooltip: 'Retour',
                icon: const Icon(Icons.arrow_back),
                onPressed: onExit,
              ),
              Expanded(
                child: PlayerTitle(title: title, subtitle: subtitle),
              ),
              TechInfo(player: player),
            ],
          ),
        ),
        // Laisse passer clics et touchers vers les gestes de l'image.
        const Spacer(),
        bar(
          top: false,
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: bottom,
          ),
        ),
      ],
    );
  }
}

/// [title] et [subtitle] sur une ligne s'ils y tiennent, sinon sur deux
/// (D-061, T-08), chacune coupée « … ».
class PlayerTitle extends StatelessWidget {
  const PlayerTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium;
    Text line(String text, {Key? key}) => Text(
      text,
      key: key,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final subtitle = this.subtitle;
    if (subtitle == null) {
      return line(title, key: const ValueKey('player.title'));
    }
    final both = '$title · $subtitle';
    return LayoutBuilder(
      builder: (context, box) =>
          fitsOnOneLine(
            both,
            DefaultTextStyle.of(context).style.merge(style),
            box.maxWidth,
            MediaQuery.textScalerOf(context),
          )
          ? line(both, key: const ValueKey('player.title'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                line(title, key: const ValueKey('player.title')),
                line(subtitle, key: const ValueKey('player.subtitle')),
              ],
            ),
    );
  }
}

/// [text] tient sur une ligne de [width] dp dans ce style.
bool fitsOnOneLine(
  String text,
  TextStyle style,
  double width,
  TextScaler scaler,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout(maxWidth: width);
  final fits = !painter.didExceedMaxLines;
  painter.dispose();
  return fits;
}
