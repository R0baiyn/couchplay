import 'package:flutter/material.dart';

import '../server/models.dart';
import 'poster_grid.dart';

/// En-tête des fiches film et série : image de fond si elle existe, affiche,
/// titre et informations. Côte à côte sur grand écran, empilés sur mobile.
/// Les champs absents ne sont pas affichés.
class DetailsHeader extends StatelessWidget {
  const DetailsHeader({super.key, required this.details});

  final Details details;

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
        final poster = SizedBox(
          width: wide ? 220 : 140,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: PosterImage(url: d.poster),
            ),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (d.backdrop case final backdrop?)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
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
              ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 24,
                      children: [
                        poster,
                        Expanded(child: text),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 16,
                      children: [poster, text],
                    ),
            ),
          ],
        );
      },
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
