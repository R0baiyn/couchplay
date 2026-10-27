import 'dart:io';

import 'package:couchplay/catalog/catalog_cache.dart';
import 'package:couchplay/catalog/catalog_repository.dart';
import 'package:couchplay/server/models.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

void main() {
  late Directory dir;
  late FakeAdapter server;
  late DateTime now;

  final categories = File('test/fixtures/vod_categories.json')
      .readAsStringSync();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('couchplay_cache_');
    server = FakeAdapter.replying(categories);
    now = DateTime.now();
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
    CatalogCache(dir),
    now: () => now,
  );

  test('premier chargement : serveur, puis cache écrit', () async {
    final loaded = await repository().categories(ContentKind.movies);
    expect(loaded.value, hasLength(36));
    expect(loaded.offline, isFalse);
    expect(server.calls, 1);
    expect(server.last!.uri.queryParameters['action'], 'get_vod_categories');
    expect(
      File('${dir.path}/catalog_movies_categories.json').existsSync(),
      isTrue,
    );
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
    File('${dir.path}/catalog_movies_categories.json').writeAsStringSync('{');
    final loaded = await repository().categories(ContentKind.movies);
    expect(loaded.value, hasLength(36));
    expect(server.calls, 1);
  });

  test('réponse illisible : erreur typée, rien en cache', () async {
    server = FakeAdapter.replying('<html>maintenance</html>');
    await expectLater(
      repository().categories(ContentKind.movies),
      throwsA(isA<InvalidResponse>()),
    );
    expect(
      File('${dir.path}/catalog_movies_categories.json').existsSync(),
      isFalse,
    );
  });

  test('liste d\'une catégorie : demandée et mise en cache à part', () async {
    server = FakeAdapter.replying(
      File('test/fixtures/series.json').readAsStringSync(),
    );
    final loaded = await repository().items(ContentKind.series, '1793');
    expect(loaded.value.first.name, 'Vikings');
    expect(
      server.last!.uri.queryParameters,
      containsPair('action', 'get_series'),
    );
    expect(
      server.last!.uri.queryParameters,
      containsPair('category_id', '1793'),
    );
    expect(
      File('${dir.path}/catalog_series_list_1793.json').existsSync(),
      isTrue,
    );
  });

  test('un id de catégorie ne peut pas sortir du dossier du cache', () async {
    await expectLater(
      repository().items(ContentKind.movies, '../x'),
      throwsArgumentError,
    );
  });
}
