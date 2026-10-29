import 'package:flutter/material.dart';

import '../server/models.dart';
import 'poster_grid.dart';

/// En-tête des fiches film et série : un bandeau, l'image de fond derrière
/// (si elle existe), l'affiche à gauche, titre, informations et résumé sur
/// toute la largeur restante. Les champs absents ne sont pas affichés.
class DetailsHeader extends StatelessWidget {
  const DetailsHeader({super.key, required this.details, this.action});

  final Details details;

  /// Bouton principal (« Lecture »), sous le titre : visible sans défiler.
  final Widget? action;

  static String _duration(Duration d) {
    final minutes = d.inMinutes;
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = details;
    final facts = [
      if (d.year case final year?) '$year',
      if (d.duration case final duration?) _duration(duration),
      if (d.rating case final rating?) '★ ${rating.toStringAsFixed(1)}',
    ].join('  ·  ');

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(d.name, style: theme.textTheme.headlineSmall),
        if (facts.isNotEmpty) Text(facts, style: theme.textTheme.titleSmall),
        if (d.genre case final genre?)
          Text(genre, style: theme.textTheme.bodyMedium),
        if (action case final action?)
          Padding(padding: const EdgeInsets.only(top: 8), child: action),
        if (d.plot case final plot?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(plot, style: theme.textTheme.bodyLarge),
          ),
        if (d.director case final director?) _Labeled('Réalisation', director),
        if (d.cast case final cast?) _Labeled('Avec', cast),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final content = Padding(
          padding: EdgeInsets.all(wide ? 24 : 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: wide ? 24 : 16,
            children: [
              SizedBox(
                width: wide ? 160 : 100,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: PosterImage(url: d.poster),
                  ),
                ),
              ),
              Expanded(child: text),
            ],
          ),
        );
        final backdrop = d.backdrop;
        if (backdrop == null) return content;
        final surface = theme.colorScheme.surface;
        // Image de fond derrière le bandeau, pas au-dessus : elle ne prend
        // aucune hauteur.
        return Stack(
          children: [
            Positioned.fill(
              child: ShaderMask(
                // Fondu vers le fond de l'écran, en bas de l'image.
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.transparent],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: PosterImage(url: backdrop),
              ),
            ),
            // Voile : le texte reste lisible sur n'importe quelle image.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      surface.withValues(alpha: 0.92),
                      surface.withValues(alpha: 0.6),
                    ],
                  ),
                ),
              ),
            ),
            content,
          ],
        );
      },
    );
  }
}

/// Barre du haut d'une fiche. Quand son focus arrive sur un de ses boutons
/// (retour, favori), la fiche remonte tout en haut : sinon, descendue à la
/// télécommande, elle y resterait.
class DetailsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DetailsAppBar({super.key, required this.scroll, required this.child});

  final ScrollController scroll;
  final AppBar child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused && scroll.hasClients) {
          scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      },
      child: child,
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label : ',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
      style: theme.textTheme.bodyMedium,
    );
  }
}
