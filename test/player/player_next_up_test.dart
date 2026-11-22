import 'package:couchplay/downloads/download.dart';
import 'package:couchplay/library/library.dart';
import 'package:couchplay/player/player_next_up.dart';
import 'package:couchplay/server/models.dart';
import 'package:flutter_test/flutter_test.dart';

PlayItem _episode(String id, int number) => PlayItem.episode(
  id: id,
  extension: 'mkv',
  name: 'Série',
  seriesId: '9',
  season: 1,
  episode: number,
);

Download _ready(PlayItem item) =>
    Download(item: item, status: DownloadStatus.ready, addedAt: DateTime(2026));

void main() {
  final first = _episode('a', 1);
  final second = _episode('b', 2);
  final downloads = [_ready(second)];

  test('fiche non chargée (hors ligne) : le suivant téléchargé', () {
    expect(nextUpFor(null, downloads, first)?.item, same(second));
    expect(nextUpFor(null, downloads, first)?.image, isNull);
    expect(nextUpFor(null, const [], first), isNull);
  });

  test('fiche chargée : elle seule décide', () {
    final series = SeriesDetails(
      details: const Details(name: 'Série'),
      seasons: [
        Season(
          number: 1,
          name: 'Saison 1',
          episodes: [
            const Episode(id: 'a', number: 1, title: 'Un', extension: 'mkv'),
            const Episode(
              id: 'c',
              number: 2,
              title: 'Deux',
              extension: 'mkv',
              image: 'vignette',
            ),
          ],
        ),
      ],
    );
    final next = nextUpFor(series, downloads, first)!;
    expect((next.item.id, next.image), ('c', 'vignette'));
    // Dernier épisode de la fiche : rien, même avec un téléchargement.
    expect(nextUpFor(series, [_ready(_episode('z', 9))], second), isNull);
  });
}
