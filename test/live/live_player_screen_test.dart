import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/app.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/live/channel.dart';
import 'package:couchplay/live/guide.dart';
import 'package:couchplay/live/live_player_screen.dart';
import 'package:couchplay/live/live_providers.dart';
import 'package:couchplay/live/live_tuner.dart';
import 'package:couchplay/player/playback.dart';
import 'package:couchplay/television.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_downloads.dart';
import '../support/fake_playback.dart';
import '../support/fixed_guide.dart';

final _channels = [
  for (var i = 1; i <= 6; i++)
    Channel(
      id: '${9000 + i}',
      name: 'Chaîne $i',
      number: i,
      epgChannelId: 'c$i.fr',
    ),
];

final _now = DateTime.utc(2026, 11, 26, 20);

/// Programme en cours de la 2e chaîne, celle de l'ouverture.
final _guide = Guide(
  channels: const {'c2.fr'},
  programmes: {
    'c2.fr': [programmeAt(_now, -600, 1800, 'Journal')],
  },
);

/// Adresse du flux d'une chaîne sur le compte d'essai.
String _url(String id) => 'http://127.0.0.1:9/live/u/p/$id.ts';

void main() {
  late Directory root;
  late FakePlayer player;
  late ProviderContainer container;

  /// Chaîne rendue par le lecteur à sa fermeture.
  Channel? returned;

  setUp(() {
    root = Directory.systemTemp.createTempSync('couchplay_live_player_');
    returned = null;
  });
  tearDown(() => root.deleteSync(recursive: true));

  Finder byKey(String key) => find.byKey(ValueKey(key));
  Finder banner(String text) => find.descendant(
    of: byKey('live.player.banner'),
    matching: find.text(text),
  );

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  /// Fait avancer l'horloge de [duration], puis quelques tours de vraie
  /// boucle : `Playback` attend la fin de ses écoutes, que Dart reprend hors
  /// de l'horloge factice.
  Future<void> run(
    WidgetTester tester, [
    Duration duration = Duration.zero,
  ]) async {
    await tester.pump(duration);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  /// Laisse passer l'attente du zapping, puis l'ouverture du flux.
  Future<void> afterZap(WidgetTester tester) => run(tester, LiveTuner.zapDelay);

  /// Fermé par Échap, laisse finir la transition et l'arrêt du flux.
  Future<void> close(WidgetTester tester) async {
    await key(tester, LogicalKeyboardKey.escape);
    await run(tester, const Duration(seconds: 1));
  }

  /// Ouvre le lecteur sur la 2e chaîne de la liste.
  /// Le faux lecteur est créé ici, dans l'horloge factice du test : ses
  /// flux y livrent leurs évènements.
  Future<void> open(
    WidgetTester tester, {
    bool television = false,
    bool refuse = false,
  }) async {
    player = FakePlayer()..refuse = refuse;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({});
    final store = await tester.runAsync(() async {
      final store = await AccountStore.open();
      await store.save(
        const AccountsState().withAccount(
          const Account(
            id: 'compte',
            name: 'Salon',
            // Une adresse IP : rien à résoudre par Cloudflare.
            host: 'http://127.0.0.1:9',
            username: 'u',
            password: 'p',
            userAgent: defaultUserAgent,
          ),
        ),
      );
      return store;
    });
    final playback = fakePlayback(player);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountStoreProvider.overrideWithValue(store!),
          accountFilesProvider.overrideWithValue(
            AccountFiles(Directory('${root.path}/accounts')),
          ),
          playbackProvider.overrideWithValue(playback),
          downloadsProvider.overrideWith(FakeDownloads.new),
          televisionProvider.overrideWithValue(television),
          guideProvider.overrideWith(() => FixedGuide(_guide)),
          guideNowProvider.overrideWithValue(() => _now),
        ],
        child: CouchPlayApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const ValueKey('test.open'),
                onPressed: () async => returned = await openLivePlayer(
                  context,
                  _channels[1],
                  _channels,
                ),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(tester.element(byKey('test.open')));
    await tester.tap(byKey('test.open'));
    await run(tester, const Duration(milliseconds: 400));
  }

  testWidgets('ouvre la chaîne choisie avec le User-Agent du compte, '
      'bandeau affiché, sans barre de temps', (tester) async {
    await open(tester);

    expect(player.urls, [_url('9002')]);
    expect(player.opened.single.httpHeaders, {'User-Agent': defaultUserAgent});
    expect(banner('2 · Chaîne 2'), findsOneWidget);
    expect(byKey('live.player.opening'), findsNothing);
    for (final film in [
      'player.progress',
      'player.rewind',
      'player.forward',
      'player.elapsed',
    ]) {
      expect(byKey(film), findsNothing, reason: film);
    }
    await close(tester);
  });

  testWidgets('↓ ↓ ↓ rapides : une seule ouverture, vers la 3e chaîne '
      'suivante, l\'ancien flux fermé d\'abord', (tester) async {
    await open(tester);
    final stops = player.stops;

    for (var i = 0; i < 3; i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 150));
    }
    // Le bandeau suit chaque appui ; le flux en cours joue toujours, ni
    // arrêté ni rouvert.
    expect(banner('5 · Chaîne 5'), findsOneWidget);
    await run(tester, const Duration(milliseconds: 1500));
    expect(player.urls, [_url('9002')]);
    expect(player.stops, stops);

    await afterZap(tester);
    expect(player.urls, [_url('9002'), _url('9005')]);
    expect(player.stops, stops + 1);
    await close(tester);
  });

  testWidgets('aperçu : OK ouvre tout de suite la chaîne affichée, un '
      'toucher du bandeau aussi', (tester) async {
    await open(tester);

    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.select);
    await run(tester);
    expect(player.urls, [_url('9002'), _url('9003')]);

    await key(tester, LogicalKeyboardKey.arrowDown);
    await tester.tap(byKey('live.player.banner'));
    await run(tester);
    expect(player.urls, [_url('9002'), _url('9003'), _url('9004')]);
    // Plus d'aperçu : rien d'autre ne s'ouvre à la fin de l'attente.
    await afterZap(tester);
    expect(player.urls, hasLength(3));
    await close(tester);
  });

  testWidgets('barres affichées (toucher, touche) : le bandeau aussi, avec '
      'le programme', (tester) async {
    await open(tester);
    await run(tester, LiveTuner.bannerFor);
    expect(byKey('live.player.banner'), findsNothing);

    await tester.tap(byKey('live.player.video'));
    await run(tester, const Duration(milliseconds: 400));
    expect(banner('2 · Chaîne 2'), findsOneWidget);
    expect(banner('Journal'), findsOneWidget);

    // Barres masquées, puis rappelées par une touche.
    await run(tester, const Duration(seconds: 4));
    expect(byKey('live.player.banner'), findsNothing);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(banner('2 · Chaîne 2'), findsOneWidget);
    await close(tester);
  });

  testWidgets('plein écran : Échap le quitte, la flèche retour quitte la '
      'chaîne', (tester) async {
    final calls = <String>[];
    const window = MethodChannel('com.alexmercerind/media_kit_video');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(window, (
      call,
    ) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        window,
        null,
      ),
    );
    await open(tester);
    Future<void> fullscreen() async {
      await tester.tap(byKey('live.player.video'));
      await run(tester, const Duration(milliseconds: 400));
      await tester.tap(byKey('live.player.fullscreen'));
      await run(tester);
    }

    await fullscreen();
    await key(tester, LogicalKeyboardKey.escape);
    await run(tester);
    expect(byKey('live.player'), findsOneWidget);
    expect(calls, [
      'Utils.EnterNativeFullscreen',
      'Utils.ExitNativeFullscreen',
    ]);

    // Barres masquées d'abord : le toucher de l'image les rappelle.
    await run(tester, const Duration(seconds: 4));
    await fullscreen();
    await tester.tap(byKey('player.back'));
    await tester.pump();
    await run(tester, const Duration(seconds: 1));
    expect(byKey('live.player'), findsNothing);
    expect(returned?.id, '9002');
    expect(calls.last, 'Utils.ExitNativeFullscreen');
  });

  testWidgets('↑ et CH− : chaîne précédente ; CH+ : suivante ; on boucle', (
    tester,
  ) async {
    await open(tester);

    await key(tester, LogicalKeyboardKey.channelUp);
    await afterZap(tester);
    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.channelDown);
    await key(tester, LogicalKeyboardKey.channelDown);
    await afterZap(tester);

    expect(player.urls, [_url('9002'), _url('9003'), _url('9006')]);
    await close(tester);
  });

  testWidgets('boutons des barres : chaîne suivante', (tester) async {
    await open(tester);

    await tester.tap(byKey('live.player.video'));
    await run(tester, const Duration(milliseconds: 400));
    await tester.tap(byKey('live.player.next'));
    await afterZap(tester);

    expect(player.urls.last, _url('9003'));
    await close(tester);
  });

  testWidgets('lecture / pause : bouton des barres et touche média (une '
      'autre app qui prend le son met en pause)', (tester) async {
    await open(tester);

    await key(tester, LogicalKeyboardKey.mediaPlayPause);
    await tester.tap(byKey('live.player.video'));
    await run(tester, const Duration(milliseconds: 400));
    await tester.tap(byKey('live.player.playPause'));
    await run(tester);

    expect(player.toggles, 2);
    await close(tester);
  });

  testWidgets('TV, barres affichées : ↓ va aux boutons au lieu de zapper', (
    tester,
  ) async {
    await open(tester, television: true);

    // Barres masquées à l'ouverture : ↓ zappe.
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(banner('3 · Chaîne 3'), findsOneWidget);
    await afterZap(tester);
    // OK affiche les barres, le focus sur le premier bouton.
    await key(tester, LogicalKeyboardKey.select);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'lecture');
    final before = player.urls.length;
    await key(tester, LogicalKeyboardKey.arrowDown);
    await afterZap(tester);
    expect(player.urls, hasLength(before));
    await close(tester);
  });

  testWidgets('retour : flux arrêté, téléchargements libérés, chaîne affichée '
      'rendue', (tester) async {
    await open(tester);
    expect(container.read(downloadHoldsProvider).streaming, isTrue);
    await key(tester, LogicalKeyboardKey.arrowDown);
    final stops = player.stops;

    await close(tester);

    expect(byKey('live.player'), findsNothing);
    expect(player.stops, stops + 1);
    expect(container.read(downloadHoldsProvider).streaming, isFalse);
    // Fermé pendant l'aperçu : la chaîne affichée est rendue, rien ne
    // s'ouvre ensuite.
    expect(returned?.id, '9003');
    await run(tester, LiveTuner.zapDelay);
    expect(player.urls, [_url('9002')]);
  });

  testWidgets('coupure : reconnexion à la même chaîne après 1 s, puis '
      'message à la 2e', (tester) async {
    await open(tester);

    player.cut();
    await tester.pump();
    expect(byKey('live.player.opening'), findsOneWidget);
    await run(tester, LiveTuner.reconnectDelay);
    expect(player.urls, [_url('9002'), _url('9002')]);
    expect(byKey('live.player.opening'), findsNothing);

    player.cut();
    await run(tester, const Duration(seconds: 5));
    expect(player.urls, hasLength(2));
    expect(byKey('live.player.error'), findsOneWidget);
    expect(find.textContaining(LiveTuner.lostMessage), findsOneWidget);
    await close(tester);
  });

  testWidgets('refus du serveur : message des films, aucun essai du direct '
      'en plus', (tester) async {
    await open(tester, refuse: true);
    // Les nouvelles tentatives de `Playback.open` (une par seconde).
    await run(tester, const Duration(seconds: 1));
    await run(tester, const Duration(seconds: 1));
    final tries = player.urls.length;
    await run(tester, const Duration(seconds: 30));

    expect(tries, 3);
    expect(player.urls, hasLength(tries));
    expect(
      find.textContaining('un autre appareil utilise peut-être'),
      findsOneWidget,
    );
    // Depuis le message, ↓ zappe (pas de touches CH sur bien des
    // télécommandes).
    player.refuse = false;
    await key(tester, LogicalKeyboardKey.arrowDown);
    await afterZap(tester);
    expect(player.urls.last, _url('9003'));
    expect(byKey('live.player.error'), findsNothing);
    // Le message parti, les touches reviennent à l'image.
    await key(tester, LogicalKeyboardKey.arrowDown);
    await afterZap(tester);
    expect(player.urls.last, _url('9004'));
    await close(tester);
  });

  /// Barres rappelées par un toucher de l'image.
  Future<void> showBars(WidgetTester tester) async {
    await tester.tap(byKey('live.player.video'));
    await run(tester, const Duration(milliseconds: 400));
  }

  double slider(WidgetTester tester) =>
      tester.widget<Slider>(byKey('player.volume')).value;

  testWidgets('volume (hors TV) : la barre le règle, le bouton coupe puis '
      'remet le son', (tester) async {
    await open(tester);
    await showBars(tester);

    await tester.tap(byKey('player.volume'));
    await run(tester);
    final chosen = player.volume;
    expect(chosen, closeTo(50, 5));
    expect(slider(tester), chosen);

    await tester.tap(byKey('player.mute'));
    await run(tester);
    expect(player.volume, 0);
    await tester.tap(byKey('player.mute'));
    await run(tester);
    expect(player.volume, chosen);
    await close(tester);
  });

  testWidgets('volume gardé d\'une chaîne à l\'autre, son coupé compris', (
    tester,
  ) async {
    await open(tester);
    await showBars(tester);
    await tester.tap(byKey('player.volume'));
    await run(tester);
    final chosen = player.volume;
    await tester.tap(byKey('player.mute'));
    await run(tester);

    await key(tester, LogicalKeyboardKey.channelUp);
    await afterZap(tester);

    expect(player.urls.last, _url('9003'));
    // Le zapping n'a rien demandé au volume.
    expect(player.volumes, [chosen, 0]);
    // Barres masquées entre-temps : le volume d'avant reste connu.
    await run(tester, const Duration(seconds: 4));
    await showBars(tester);
    expect(slider(tester), 0);
    await tester.tap(byKey('player.mute'));
    await run(tester);
    expect(player.volume, chosen);
    await close(tester);
  });

  testWidgets('TV : ni bouton ni barre de volume (la télécommande règle '
      'celui de l\'appareil)', (tester) async {
    await open(tester, television: true);
    await key(tester, LogicalKeyboardKey.select);

    expect(byKey('live.player.playPause'), findsOneWidget);
    expect(byKey('player.mute'), findsNothing);
    expect(byKey('player.volume'), findsNothing);
    await close(tester);
  });

  testWidgets('téléphone en paysage (800 × 360) : la rangée avec le volume '
      'ne déborde pas', (tester) async {
    await open(tester);
    tester.view.physicalSize = const Size(800, 360);
    await showBars(tester);
    // Fondu fini : un débordement n'est signalé que si la rangée est peinte.
    await tester.pump(const Duration(milliseconds: 300));

    expect(byKey('player.volume'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });
}
