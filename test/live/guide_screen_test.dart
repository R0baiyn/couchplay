import 'dart:convert';
import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/accounts/server_session.dart';
import 'package:couchplay/app.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/live/guide.dart';
import 'package:couchplay/live/guide_cell_view.dart';
import 'package:couchplay/live/guide_layout.dart';
import 'package:couchplay/live/live_providers.dart';
import 'package:couchplay/live/live_screen.dart';
import 'package:couchplay/live/live_tuner.dart';
import 'package:couchplay/player/playback.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_downloads.dart';
import '../support/fake_playback.dart';
import '../support/fake_server.dart';
import '../support/fixed_guide.dart';
import '../support/settle.dart';

String _fixture(String name) =>
    File('test/fixtures/$name.json').readAsStringSync();

void main() {
  // L'axe part de 18:00 (maintenant − 2 h, à la demi-heure).
  final now = DateTime.utc(2026, 11, 25, 20, 10);
  late Directory root;
  late FakePlayer player;

  setUp(() => root = Directory.systemTemp.createTempSync('couchplay_guide_'));
  tearDown(() => root.deleteSync(recursive: true));

  /// Programme de [a] à [b] minutes après maintenant.
  Programme p(int a, int b, String title, [String? description]) => Programme(
    start: now.add(Duration(minutes: a)),
    stop: now.add(Duration(minutes: b)),
    title: title,
    description: description,
  );

  // Catégorie 104 : 9001 (chaine1), 9002 (chaine2), 9003 (sans id de guide),
  // 9004 (absente du guide), 9005 (sans programme).
  final guide = Guide(
    channels: const {'chaine1.test', 'chaine2.test', 'sansprogramme.test'},
    programmes: {
      'chaine1.test': [
        p(-60, 30, 'Journal'),
        p(30, 90, 'Film', 'Un film du soir.'),
        p(90, 150, 'Débat'),
      ],
      'chaine2.test': [p(-60, 20, 'Série'), p(20, 60, 'Météo')],
    },
  );

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    Guide? withGuide,
    String? streams,
    bool open = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({});
    player = FakePlayer();
    Directory('${root.path}/accounts/compte').createSync(recursive: true);
    final store = await tester.runAsync(() async {
      final store = await AccountStore.open();
      await store.save(
        const AccountsState().withAccount(
          const Account(
            id: 'compte',
            name: 'Salon',
            host: 'http://127.0.0.1:9',
            username: 'u',
            password: 'p',
            userAgent: defaultUserAgent,
          ),
        ),
      );
      return store;
    });
    final server = FakeAdapter.routes({
      'get_live_categories': _fixture('live_categories'),
      'get_live_streams': streams ?? _fixture('live_streams'),
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
          guideProvider.overrideWith(() => FixedGuide(withGuide ?? guide)),
          guideNowProvider.overrideWithValue(() => now),
        ],
        child: const CouchPlayApp(home: LiveScreen()),
      ),
    );
    await settle(tester);
    if (!open) return;
    await tester.tap(find.byKey(const ValueKey('live.guide.open')));
    await settle(tester);
  }

  Finder byKey(String key) => find.byKey(ValueKey(key));
  String cell(String channel, int minutes) =>
      'live.guide.$channel.'
      '${now.add(Duration(minutes: minutes)).millisecondsSinceEpoch ~/ 1000}';

  /// Key de la case qui a le focus, ou null.
  String? focused() {
    final context = FocusManager.instance.primaryFocus?.context;
    final key = context?.findAncestorWidgetOfExactType<GuideCell>()?.key;
    return key is ValueKey<String> ? key.value : null;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  List<String> opened() => [
    for (final url in player.urls) url.split('/').last.split('.').first,
  ];

  testWidgets('ouverte sur maintenant : le programme en cours a le focus, '
      'le trait « maintenant » est à l’écran', (tester) async {
    await pump(tester);

    expect(byKey('live.guide'), findsOneWidget);
    expect(focused(), cell('9001', -60));
    expect(byKey('live.guide.nowLine'), findsOneWidget);
    final grid = tester.getRect(byKey('live.guide.grid'));
    final line = tester.getRect(byKey('live.guide.nowLine'));
    expect(grid.contains(line.center), isTrue);
    // Les chaînes sans programme ont leur case.
    for (final id in ['9003', '9004', '9005']) {
      expect(
        find.descendant(
          of: byKey(
            'live.guide.$id.${DateTime.utc(2026, 11, 25, 18).millisecondsSinceEpoch ~/ 1000}',
          ),
          matching: find.text('Pas de programme'),
        ),
        findsOneWidget,
        reason: id,
      );
    }
  });

  testWidgets('OK sur le programme en cours : la chaîne, zapping dans la '
      'catégorie', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await settle(tester);

    expect(byKey('live.player'), findsOneWidget);
    expect(opened(), ['9001']);
    // La liste de la catégorie est passée au lecteur : ↓ zappe sur 9002.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(LiveTuner.zapDelay);
    await settle(tester);
    expect(opened(), ['9001', '9002']);
  });

  testWidgets('← → changent de programme sur la même chaîne', (tester) async {
    await pump(tester);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), cell('9001', 30));
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), cell('9001', 90));
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focused(), cell('9001', 30));
  });

  testWidgets('↓ garde l’heure : ↓ ↓ ↑ ↑ revient au même programme', (
    tester,
  ) async {
    await pump(tester);
    // « Film » commence à + 30 min.
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), cell('9001', 30));
    // Sur chaine2, + 30 min tombe dans « Météo », pas dans « Série » (en
    // cours).
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), cell('9002', 20));
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), startsWith('live.guide.9003.'));
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focused(), cell('9002', 20));
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focused(), cell('9001', 30));
  });

  testWidgets('programme à venir : son détail, puis « Regarder la chaîne »', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(byKey(cell('9001', 30)));
    await settle(tester);

    expect(byKey('live.guide.detail'), findsOneWidget);
    expect(find.text('Un film du soir.'), findsOneWidget);
    expect(opened(), isEmpty);
    await tester.tap(byKey('live.guide.watch'));
    await settle(tester);
    expect(opened(), ['9001']);
  });

  testWidgets('« Maintenant » ramène au programme en cours', (tester) async {
    await pump(tester);
    for (var i = 0; i < 2; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    await tester.tap(byKey('live.guide.now'));
    await tester.pumpAndSettle();
    expect(focused(), cell('9001', -60));
  });

  /// 300 chaînes de la catégorie 104, une émission par demi-heure sur
  /// 3 jours.
  String bigStreams() => jsonEncode([
    for (var i = 0; i < 300; i++)
      {
        'num': i + 1,
        'name': 'Chaîne $i',
        'stream_type': 'live',
        'stream_id': 20000 + i,
        'epg_channel_id': 'c$i.test',
        'category_id': '104',
      },
  ]);
  Guide bigGuide() {
    final programmes = {
      for (var i = 0; i < 300; i++)
        'c$i.test': [
          for (var m = -120; m < 3 * 24 * 60; m += 30)
            p(m, m + 30, 'Émission $i $m'),
        ],
    };
    return Guide(channels: programmes.keys.toSet(), programmes: programmes);
  }

  int built() => find.byType(GuideCell, skipOffstage: false).evaluate().length;

  testWidgets('focus qui sort de l’écran : la grille défile pour le suivre', (
    tester,
  ) async {
    await pump(
      tester,
      size: const Size(960, 540),
      streams: bigStreams(),
      withGuide: bigGuide(),
    );
    final grid = tester.getRect(byKey('live.guide.grid'));
    void expectShown(String key) {
      expect(focused(), key);
      final rect = tester.getRect(byKey(key));
      expect(
        grid.contains(rect.topLeft) && grid.contains(rect.bottomRight),
        isTrue,
        reason: '$rect hors de $grid',
      );
    }

    for (var i = 0; i < 25; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    expectShown(cell('20025', 0));
    for (var i = 1; i <= 15; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    expectShown(cell('20025', 15 * 30));
    expect(built(), inInclusiveRange(1, 400));
    // Retour en haut à l'heure tenue.
    for (var i = 0; i < 25; i++) {
      await press(tester, LogicalKeyboardKey.arrowUp);
    }
    expectShown(cell('20000', 15 * 30));
  });

  testWidgets('télécommande seule : ouvrir le guide, ↑ vers « Maintenant », '
      'retour sur le bouton du guide', (tester) async {
    await pump(tester, open: false);
    String? key() {
      final context = FocusManager.instance.primaryFocus?.context;
      final button = context?.findAncestorWidgetOfExactType<IconButton>();
      final text = context?.findAncestorWidgetOfExactType<TextButton>();
      return switch (button?.key ?? text?.key) {
        ValueKey<String>(:final value) => value,
        _ => null,
      };
    }

    for (var i = 0; key() != 'live.guide.open'; i++) {
      if (i == 30) fail('bouton du guide jamais atteint au clavier');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(focused(), cell('9001', -60));

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(key(), 'live.guide.now');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), startsWith('live.guide.9001.'));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(byKey('live.guide'), findsNothing);
    expect(key(), 'live.guide.open');
  });

  testWidgets('300 chaînes × 3 jours : seules les cases en vue sont '
      'construites, aussi après un saut sur chaque axe', (tester) async {
    await pump(tester, streams: bigStreams(), withGuide: bigGuide());

    // 1280 × 800 : une quinzaine de lignes, une dizaine de cases chacune.
    expect(built(), inInclusiveRange(1, 400));
    final grid = byKey('live.guide.grid');
    await tester.drag(grid, const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(built(), inInclusiveRange(1, 400));
    expect(
      find.byKey(const ValueKey('live.guide.channel.20000')),
      findsNothing,
    );
    await tester.drag(grid, const Offset(-8000, 0));
    await tester.pumpAndSettle();
    expect(built(), inInclusiveRange(1, 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('téléphone en portrait : colonne réduite au logo, rien ne '
      'déborde', (tester) async {
    await pump(tester, size: const Size(360, 740));

    expect(byKey('live.guide.channel.9001'), findsOneWidget);
    expect(
      find.descendant(
        of: byKey('live.guide.channel.9001'),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    expect(focused(), cell('9001', -60));
    expect(tester.takeException(), isNull);
  });

  testWidgets('largeur de l’axe : jusqu’à la fin des données', (tester) async {
    await pump(tester);
    final layout = ProviderScope.containerOf(
      tester.element(byKey('live.guide')),
    ).read(guideLayoutProvider('104'));
    // Fin des données à 22:40, arrondie à la demi-heure.
    expect(layout.from, DateTime.utc(2026, 11, 25, 18));
    expect(layout.to, DateTime.utc(2026, 11, 25, 23));
    expect(layout.width, 5 * 60 * GuideLayout.pixelsPerMinute);
  });
}
