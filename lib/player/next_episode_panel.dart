import 'package:flutter/material.dart';

import '../poster_image.dart';

/// « Épisode suivant dans 10 s », en bas à droite, par-dessus la fin.
class NextEpisodePanel extends StatelessWidget {
  const NextEpisodePanel({
    super.key,
    required this.title,
    required this.image,
    required this.secondsLeft,
    required this.playNowFocus,
    required this.onPlayNow,
    required this.onCancel,
  });

  final String title;
  final String? image;
  final int secondsLeft;
  final FocusNode playNowFocus;
  final VoidCallback onPlayNow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      key: const ValueKey('player.nextPanel'),
      margin: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text(
                'Épisode suivant dans $secondsLeft s',
                style: text.titleMedium,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  SizedBox(
                    width: 120,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: PosterImage(url: image, icon: Icons.tv),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    key: const ValueKey('player.nextCancel'),
                    onPressed: onCancel,
                    child: const Text('Annuler'),
                  ),
                  FilledButton(
                    key: const ValueKey('player.nextPlay'),
                    focusNode: playNowFocus,
                    onPressed: onPlayNow,
                    child: const Text('Lire maintenant'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
