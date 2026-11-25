import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/accounts/server_session.dart';
import 'package:couchplay/app.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/live/live_screen.dart';
import 'package:couchplay/live/live_tuner.dart';
import 'package:couchplay/player/playback.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_downloads.dart';
import '../support/fake_playback.dart';
import '../support/fake_server.dart';
import '../support/settle.dart';

String _fixture(String name) =>
    File('test/fixtures/$name.json').readAsStringSync();

void main() {
  late Directory root;
  late HttpClientAdapter server;
  late FakePlayer player;

  FakeAdapter routes() => FakeAdapter.routes({
    'get_live_categories': _fixture('live_categories'),
    'get_live_streams': _fixture('live_streams'),
  });

  setUp(() {
    root = Directory.systemTemp.createTempSync('couchplay_live_screen_');
    server = routes();
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    String? settings,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({});
    // Créé dans l'horloge factice du test (voir `FakePlayer`).
    player = FakePlayer();
    final account = Directory('${root.path}/accounts/compte')
      ..createSync(recursive: true);
    if (settings != null) {
      File('${account.path}/catalog_settings.json').writeAsStringSync(settings);
    }
    final store = await tester.runAsync(() async {
      final store = await AccountStore.open();
      await store.save(
        const AccountsState().withAccount(
          const Account(
            id: 'compte',
            name: 'Salon',
            // Une adresse IP : le lecteur n'a rien à résoudre par Cloudflare.
            host: 'http://127.0.0.1:9',
            username: 'u',
            password: 'p',
            userAgent: defaultUserAgent,
          ),
        ),
      );
      return store;
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountStoreProvider.overrideWithValue(store!),
          accountFilesProvider.overrideWithValue(
            AccountFiles(Directory('${root.path}/accounts')),
          ),
          playbackProvider.overrideWithValue(fakePlayback(player)),
          downloadsProvider.overrideWith(FakeDownloads.new),
          serverClientFactoryProvider.overrideWithValue(
            (a) => ServerClient(
              host: a.host,
              username: a.username,
              password: a.password,
              userAgent: a.userAgent,
              adapter: server,
            ),
          ),
        ],
        child: const CouchPlayApp(home: LiveScreen()),
      ),
    );
    await settle(tester);
  }

  Finder byKey(String key) => find.byKey(ValueKey(key));
  Finder inChannel(String id, Finder finder) =>
      find.descendant(of: byKey('live.channel.$id'), matching: finder);

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(byKey(key));
    await settle(tester);
  }

  /// Id de la chaîne qui a le focus, ou null.
  String? focused() {
    final context = FocusManager.instance.primaryFocus?.context;
    final key = context?.findAncestorWidgetOfExactType<ListTile>()?.key;
    return key is ValueKey<String> && key.value.startsWith('live.channel.')
        ? key.value.substring('live.channel.'.length)
        : null;
  }

  testWidgets('catégories visibles, et les chaînes de la première avec leur '
      'numéro et leur nom', (tester) async {
    await pump(tester);

    expect(byKey('live.categoryTile.104'), findsOneWidget);
    expect(byKey('live.categoryTile.1'), findsOneWidget);
    // BELGIUM : masquée par le filtre du compte.
    expect(byKey('live.categoryTile.60'), findsNothing);
    expect(inChannel('9001', find.text('Chaîne 1 HD')), findsOneWidget);
    expect(inChannel('9001', find.text('1')), findsOneWidget);
    // FHD, pas encore choisie.
    expect(byKey('live.channel.9006'), findsNothing);

    await tap(tester, 'live.categoryTile.1');
    expect(byKey('live.channel.9006'), findsOneWidget);
    expect(byKey('live.channel.9001'), findsNothing);
  });

  testWidgets('logo vide ou en échec : icône de repli', (tester) async {
    await pump(tester);
    // 9003 : sans logo. 9001 : adresse qui ne répond pas (400 en test).
    expect(inChannel('9003', find.byType(Image)), findsNothing);
    expect(inChannel('9003', find.byIcon(Icons.live_tv)), findsOneWidget);
    expect(inChannel('9001', find.byIcon(Icons.live_tv)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('écran étroit : la catégorie se choisit dans le panneau', (
    tester,
  ) async {
    await pump(tester, size: const Size(360, 740));
    expect(byKey('live.categoryTile.104'), findsNothing);
    await tap(tester, 'live.categoryPicker');
    await tap(tester, 'live.categorySheetTile.1');
    expect(byKey('live.channel.9006'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /// Chaînes dont le flux a été ouvert, dans l'ordre.
  List<String> opened() => [
    for (final url in player.urls) url.split('/').last.split('.').first,
  ];

  testWidgets('toucher une chaîne l\'ouvre', (tester) async {
    await pump(tester);
    await tap(tester, 'live.channel.9002');
    expect(byKey('live.player'), findsOneWidget);
    expect(opened(), ['9002']);
  });

  testWidgets('retour du lecteur : le focus sur la dernière chaîne regardée', (
    tester,
  ) async {
    await pump(tester);
    await tap(tester, 'live.channel.9001');
    // Zapping dans la catégorie affichée : 9001 → 9003.
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.pump(LiveTuner.zapDelay);
    await settle(tester);
    expect(opened(), ['9001', '9003']);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    expect(byKey('live.player'), findsNothing);
    expect(focused(), '9003');
  });

  testWidgets('clavier : les flèches parcourent la liste, OK ouvre', (
    tester,
  ) async {
    await pump(tester);
    for (var i = 0; focused() == null; i++) {
      if (i == 20) fail('aucune chaîne atteinte au clavier');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    final first = focused()!;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final second = focused();
    expect(second, isNotNull);
    expect(second, isNot(first));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focused(), first);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await settle(tester);
    expect(byKey('live.player'), findsOneWidget);
    expect(opened(), [first]);
  });

  testWidgets('erreur du serveur : « Réessayer » recharge', (tester) async {
    var broken = true;
    final online = routes();
    server = FakeAdapter(
      (options) => broken
          ? Future.value(ResponseBody.fromString('', 500))
          : online.fetch(options, null, null),
    );
    await pump(tester);
    expect(byKey('live.error'), findsOneWidget);

    broken = false;
    await tester.tap(
      find.descendant(
        of: byKey('live.error'),
        matching: byKey('catalog.errorRetry'),
      ),
    );
    await settle(tester);
    expect(byKey('live.error'), findsNothing);
    expect(byKey('live.channel.9001'), findsOneWidget);
  });

  testWidgets('« Actualiser » sans réseau : la liste reste, avec le bandeau '
      'hors ligne', (tester) async {
    var down = false;
    final online = routes();
    server = FakeAdapter((options) {
      if (down) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      return online.fetch(options, null, null);
    });
    await pump(tester);
    expect(byKey('live.offlineBanner'), findsNothing);

    down = true;
    await tap(tester, 'live.refresh');
    expect(byKey('live.offlineBanner'), findsOneWidget);
    expect(byKey('live.channel.9001'), findsOneWidget);
  });

  testWidgets('aucune catégorie visible : renvoi vers les réglages', (
    tester,
  ) async {
    await pump(tester, settings: '{"tags":["ZZ"]}');
    expect(byKey('live.noCategory'), findsOneWidget);
    expect(find.textContaining('réglages'), findsOneWidget);
  });
}
