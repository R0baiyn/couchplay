import 'dart:io';

import 'package:couchplay/catalog/catalog_cache.dart';
import 'package:couchplay/catalog/catalog_repository.dart';
import 'package:couchplay/search/search_index.dart';

import 'package:couchplay/server/models.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

void main() {
  late Directory dir;
  late FakeAdapter server;
  late DateTime now;
  var serverKey = 'serveur-a';

  final categories = File('test/fixtures/vod_categories.json')
      .readAsStringSync();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('couchplay_cache_');
    server = FakeAdapter.replying(categories);
    now = DateTime.now();
    serverKey = 'serveur-a';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  CatalogRepository repository() => CatalogRepository(
    ServerClient(
      host: 'http://example.com',
      username: 'u',
      password: 'p',
      userAgent: 'test',
      adapter: server,
    ),
    CatalogCache(dir, serverKey: serverKey),
    now: () => now,
  );

  test('premier chargement : serveur, puis cache écrit', () async {
    final loaded = await repository().categories(ContentKind.movies);
    expect(loaded.value, hasLength(36));
    expect(loaded.offline, isFalse);
    expect(server.calls, 1);
    expect(server.last!.uri.queryParameters['action'], 'get_vod_categories');
    expect(File('${dir.path}/movies_categories.json').existsSync(), isTrue);
  });

  test('cache récent : aucun appel réseau', () async {
    await repository().categories(ContentKind.movies);
    final loaded = await repository().categories(ContentKind.movies);
    expect(loaded.value, hasLength(36));
    expect(loaded.savedAt, isNotNull);
    expect(server.calls, 1);
  });

  test('« Actualiser » ou cache de plus de 24 h : retour au serveur', () async {
    await repository().categories(ContentKind.movies);
    await repository().categories(ContentKind.movies, refresh: true);
    expect(server.calls, 2);

    now = now.add(const Duration(hours: 25));
    await repository().categories(ContentKind.movies);
    expect(server.calls, 3);
  });

  test(
    'hors ligne avec un cache périmé : le cache, marqué hors ligne',
    () async {
      await repository().categories(ContentKind.movies);
      now = now.add(const Duration(days: 3));
      server = FakeAdapter.failing(DioExceptionType.connectionError);

      final loaded = await repository().categories(ContentKind.movies);
      expect(loaded.offline, isTrue);
      expect(loaded.value, hasLength(36));
    },
  );

  test(
    'fiche d\'une série : 1 h pour la fiche, 24 h pour l\'accueil',
    () async {
      server = FakeAdapter.replying(
        File('test/fixtures/series_info.json').readAsStringSync(),
      );
      final first = await repository().series('1');
      expect(first.seasons, isNotEmpty);
      await repository().series('1');
      expect(server.calls, 1, reason: 'repasser sur la fiche');

      now = now.add(const Duration(hours: 2));
      await repository().cachedSeries('1');
      expect(server.calls, 1, reason: 'l\'accueil se contente du cache');
      await repository().series('1');
      expect(server.calls, 2, reason: 'la fiche veut moins d\'une heure');
    },
  );

  test('hors ligne sans cache : l\'erreur remonte', () async {
    server = FakeAdapter.failing(DioExceptionType.connectionError);
    await expectLater(
      repository().categories(ContentKind.movies),
      throwsA(isA<ServerUnreachable>()),
    );
  });

  test('identifiants refusés : jamais masqués par le cache', () async {
    await repository().categories(ContentKind.movies);
    server = FakeAdapter.replying('{"user_info":{"auth":0}}', status: 404);
    await expectLater(
      repository().categories(ContentKind.movies, refresh: true),
      throwsA(isA<CredentialsRejected>()),
    );
  });

  test('cache corrompu : ignoré, le serveur répond', () async {
    await repository().categories(ContentKind.movies);
    File('${dir.path}/movies_categories.json').writeAsStringSync('{');
    final loaded = await repository().categories(ContentKind.movies);
    expect(loaded.value, hasLength(36));
    expect(server.calls, 2);
  });

  test('changer d\'adresse ou d\'utilisateur efface l\'ancien cache', () async {
    await repository().categories(ContentKind.movies);
    serverKey = 'serveur-b';
    await repository().categories(ContentKind.movies);
    expect(server.calls, 2, reason: 'le cache du serveur A ne sert pas pour B');
  });

  test('réponse illisible : erreur typée, rien en cache', () async {
    server = FakeAdapter.replying('<html>maintenance</html>');
    await expectLater(
      repository().categories(ContentKind.movies),
      throwsA(isA<InvalidResponse>()),
    );
    expect(File('${dir.path}/movies_categories.json').existsSync(), isFalse);
  });

  test('un id inutilisable comme nom de fichier : pas de cache', () async {
    server = FakeAdapter.replying(
      File('test/fixtures/vod_info.json').readAsStringSync(),
    );
    final movie = await repository().movie('../x');
    expect(movie.details.name, isNotEmpty);
    expect(
      dir.listSync().whereType<File>().map((f) => f.path),
      isNot(contains(endsWith('.json'))),
    );
  });

  test('statut 200 avec auth à 0 : refusé, et le cache reste intact', () async {
    await repository().categories(ContentKind.movies);
    server = FakeAdapter.replying('{"user_info":{"auth":0}}');
    await expectLater(
      repository().categories(ContentKind.movies, refresh: true),
      throwsA(isA<CredentialsRejected>()),
    );
    server = FakeAdapter.failing(DioExceptionType.connectionError);
    now = now.add(const Duration(days: 2));
    final loaded = await repository().categories(ContentKind.movies);
    expect(loaded.value, hasLength(36));
  });

  // Régression : avec un vrai client http, la fonction de décodage envoyée à
  // l'isolate ne doit pas emporter le client (objet impossible à envoyer).
  test('liste complète avec un vrai serveur http local', () async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(http.close);
    final body = File('test/fixtures/vod_streams.json').readAsStringSync();
    http.listen((request) {
      request.response
        ..headers.contentType = ContentType.json
        ..write(body)
        ..close();
    });
    final client = ServerClient(
      host: 'http://127.0.0.1:${http.port}',
      username: 'u',
      password: 'p',
      userAgent: 'test',
    );
    addTearDown(client.close);
    final repository = CatalogRepository(
      client,
      CatalogCache(dir, serverKey: serverKey),
    );

    final parse = indexParser(ContentKind.movies, {'148'});
    final loaded = await repository.all(ContentKind.movies, parse);
    expect(loaded.value.entriesIn('148')!.first.title, 'Libre (2024)');
    final again = await repository.all(ContentKind.movies, parse);
    expect(again.savedAt, isNotNull, reason: 'relu depuis le cache');
  });
}
