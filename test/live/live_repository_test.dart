import 'dart:io';

import 'package:couchplay/catalog/catalog_cache.dart';
import 'package:couchplay/live/live_repository.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

void main() {
  late Directory dir;
  late FakeAdapter server;
  late DateTime now;

  final routes = {
    'get_live_categories': File('test/fixtures/live_categories.json')
        .readAsStringSync(),
    'get_live_streams': File('test/fixtures/live_streams.json')
        .readAsStringSync(),
  };

  setUp(() {
    dir = Directory.systemTemp.createTempSync('couchplay_live_');
    server = FakeAdapter.routes(routes);
    now = DateTime.now();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  LiveRepository repository() => LiveRepository(
    ServerClient(
      host: 'http://example.com',
      username: 'u',
      password: 'p',
      userAgent: 'test',
      adapter: server,
    ),
    CatalogCache(dir, serverKey: 'serveur-a'),
    now: () => now,
  );

  test('premier chargement : serveur, puis cache propre au direct', () async {
    final categories = await repository().categories();
    expect(categories.value, hasLength(13));
    expect(server.last!.uri.queryParameters['action'], 'get_live_categories');
    final channels = await repository().channels();
    expect(channels.value, hasLength(20));
    expect(channels.offline, isFalse);
    expect(server.last!.uri.queryParameters['action'], 'get_live_streams');
    expect(server.calls, 2);
    expect(File('${dir.path}/live_categories.json').existsSync(), isTrue);
    expect(File('${dir.path}/live_streams.json').existsSync(), isTrue);
  });

  test('cache récent : aucun appel réseau', () async {
    await repository().channels();
    final loaded = await repository().channels();
    expect(loaded.value, hasLength(20));
    expect(loaded.savedAt, isNotNull);
    expect(server.calls, 1);
  });

  test('« Actualiser » ou cache de plus de 24 h : retour au serveur', () async {
    await repository().channels();
    await repository().channels(refresh: true);
    expect(server.calls, 2);

    now = now.add(const Duration(hours: 25));
    await repository().channels();
    expect(server.calls, 3);
  });

  test('serveur muet avec un cache périmé : le cache, hors ligne', () async {
    await repository().categories();
    await repository().channels();
    now = now.add(const Duration(days: 3));
    server = FakeAdapter.failing(DioExceptionType.connectionTimeout);

    final categories = await repository().categories();
    final channels = await repository().channels();
    expect(categories.offline, isTrue);
    expect(channels.offline, isTrue);
    expect(channels.value, hasLength(20));
    expect(channels.savedAt, isNotNull);
  });

  test('serveur muet sans cache : l’erreur remonte', () async {
    server = FakeAdapter.failing(DioExceptionType.connectionError);
    await expectLater(
      repository().channels(),
      throwsA(isA<ServerUnreachable>()),
    );
  });
}
