import 'dart:io';

import 'package:couchplay/server/models.dart';
import 'package:flutter_test/flutter_test.dart';

String _fixture(String name) =>
    File('test/fixtures/$name.json').readAsStringSync();

void main() {
  group('catégories', () {
    test('lit toutes les catégories de la fixture', () {
      final categories = parseCategories(_fixture('vod_categories'));
      expect(categories, hasLength(36));
      expect(categories.first.id, '619');
      expect(categories.first.name, 'Films 4K');
    });

    test('ignore les entrées sans id ou sans nom', () {
      final categories = parseCategories(
        '[{"category_id":"1","category_name":"A"},{"category_id":"2"},'
        '{"category_name":"B"},"texte",{"category_id":3,"category_name":" C "}]',
      );
      expect(categories.map((c) => (c.id, c.name)), [('1', 'A'), ('3', 'C')]);
    });
  });

  group('listes', () {
    test(
      'films : id, affiche, tmdb et extension, quels que soient les types',
      () {
        final movies = parseCatalogItems(
          _fixture('vod_streams'),
          ContentKind.movies,
        );
        // 9 entrées, dont une au nom vide (vraie donnée du serveur) : ignorée.
        expect(movies, hasLength(8));
        final libre = movies.first;
        expect(libre.id, '144014');
        expect(libre.name, 'Libre (2024) HD VF');
        expect(libre.tmdbId, '1142518');
        expect(libre.extension, 'mp4');
        expect(libre.poster, startsWith('https://image.tmdb.org/'));
        // tmdb_id en entier dans la réponse : lu en texte comme les autres.
        expect(movies.firstWhere((m) => m.id == '122716').tmdbId, '9837');
      },
    );

    test('séries : id et couverture', () {
      final series = parseCatalogItems(_fixture('series'), ContentKind.series);
      expect(series, hasLength(5));
      expect(series.first.id, '17');
      expect(series.first.name, 'Vikings');
      expect(series.first.extension, isNull);
    });

    test('une entrée invalide est ignorée, pas toute la liste', () {
      final items = parseCatalogItems(
        '[{"stream_id":1,"name":"A","stream_icon":"/relatif.jpg","tmdb":"0"},'
        '{"name":"sans id"},null,{"stream_id":"2","name":""}]',
        ContentKind.movies,
      );
      expect(items, hasLength(1));
      expect(items.single.poster, isNull);
      expect(items.single.tmdbId, isNull);
    });
  });

  group('fiche film', () {
    test('version complète', () {
      final movie = parseMovieDetails(_fixture('vod_info'));
      final d = movie.details;
      expect(d.name, 'Libre (2024) FHD VF');
      expect(d.year, 2024);
      expect(d.duration, const Duration(hours: 1, minutes: 50, seconds: 30));
      expect(d.genre, 'Action, Romance, Drame');
      expect(d.rating, closeTo(6.586, 0.001));
      expect(d.director, 'Mélanie Laurent');
      expect(d.cast, startsWith('Lucas Bravo'));
      expect(d.plot, startsWith('Inspiré de faits réels'));
      expect(d.backdrop, startsWith('https://image.tmdb.org/t/p/w1280/'));
      expect(movie.extension, 'mkv');
    });

    test('version minimale ou mal typée : champs absents à null', () {
      final movie = parseMovieDetails(
        '{"info":[],"movie_data":{"name":"Titre (1999)","container_extension":"avi"}}',
      );
      final d = movie.details;
      expect(d.name, 'Titre (1999)');
      expect(d.year, 1999);
      expect(d.duration, isNull);
      expect(d.rating, isNull);
      expect(d.poster, isNull);
      expect(d.backdrop, isNull);
      expect(movie.extension, 'avi');
    });

    test('réponse vide du serveur : fiche « Sans titre », sans planter', () {
      expect(
        parseMovieDetails('{"info":[],"movie_data":[]}').details.name,
        'Sans titre',
      );
    });
  });

  group('fiche série', () {
    test('saisons depuis les épisodes, pas depuis la liste TMDB', () {
      final series = parseSeriesDetails(_fixture('series_info'));
      expect(series.details.name, 'Vikings');
      // La fixture garde 2 saisons de 3 épisodes ; la saison 0 de `seasons`
      // n'a aucun épisode et n'apparaît pas.
      expect(series.seasons.map((s) => s.number), [1, 2]);
      expect(series.seasons.first.name, 'Saison 1');
      expect(series.seasons.first.episodes.map((e) => e.number), [1, 2, 3]);
      final first = series.seasons.first.episodes.first;
      expect(first.id, '6912');
      expect(first.extension, 'mkv');
      expect(first.duration, isNull, reason: 'durée à 0 dans la fixture');
    });

    test('saisons en chaînes et épisodes dans le désordre', () {
      final series = parseSeriesDetails('''
{"info":{"name":"S"},"seasons":[],"episodes":{
  "10":[{"id":"c","episode_num":"2"},{"id":"d","episode_num":1}],
  "2":[{"id":"a","episode_num":"3","info":{"duration_secs":"1500"}},
       {"id":"b","episode_num":"1","title":"Pilote"}],
  "0":[{"id":"e","episode_num":1}],
  "3":[],
  "x":[{"id":"f","episode_num":1}]
}}''');
      expect(series.seasons.map((s) => s.number), [0, 2, 10]);
      expect(series.seasons.first.name, 'Épisodes spéciaux');
      expect(series.seasons[1].episodes.map((e) => e.id), ['b', 'a']);
      expect(series.seasons[1].episodes.first.title, 'Pilote');
      expect(series.seasons[1].episodes.last.title, 'Épisode 3');
      expect(
        series.seasons[1].episodes.last.duration,
        const Duration(minutes: 25),
      );
      expect(series.seasons[2].episodes.map((e) => e.id), ['d', 'c']);
    });
  });
}
