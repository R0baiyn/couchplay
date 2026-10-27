import 'package:couchplay/library/library.dart';
import 'package:couchplay/server/models.dart';
import 'package:flutter_test/flutter_test.dart';

Episode _episode(String id, int number, {String? extension = 'mkv'}) => Episode(
  id: id,
  number: number,
  title: 'Épisode $number',
  extension: extension,
);

final _series = SeriesDetails(
  details: const Details(name: 'Série'),
  seasons: [
    Season(
      number: 1,
      name: 'Saison 1',
      episodes: [_episode('a', 1), _episode('b', 2)],
    ),
    // Aucun fichier connu : saison sautée.
    Season(
      number: 2,
      name: 'Saison 2',
      episodes: [_episode('c', 1, extension: null)],
    ),
    Season(
      number: 3,
      name: 'Saison 3',
      episodes: [_episode('d', 1, extension: null), _episode('e', 2)],
    ),
  ],
);

PlayItem _playing(String id) => PlayItem.episode(
  id: id,
  extension: 'mkv',
  name: 'Série',
  seriesId: '9',
  season: 1,
  episode: 1,
  poster: 'affiche',
);

void main() {
  test('même saison', () {
    final next = nextEpisode(_series, _playing('a'))!.item;
    expect(next.id, 'b');
    expect((next.season, next.episode), (1, 2));
    expect((next.name, next.seriesId, next.poster), ('Série', '9', 'affiche'));
  });

  test('saison suivante, épisodes et saison sans fichier sautés', () {
    final next = nextEpisode(_series, _playing('b'))!.item;
    expect(next.id, 'e');
    expect((next.season, next.episode), (3, 2));
  });

  test('fin de série, ou épisode disparu : rien', () {
    expect(nextEpisode(_series, _playing('e')), isNull);
    expect(nextEpisode(_series, _playing('inconnu')), isNull);
  });
}
