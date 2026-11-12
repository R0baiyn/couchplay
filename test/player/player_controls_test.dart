import 'package:couchplay/app.dart';
import 'package:couchplay/player/player_controls.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// Lecteur sans libmpv : en lecture, aucun flux, chaque appel compté.
class _FakePlayer implements Player {
  final calls = <Symbol>[];

  /// Positions demandées par `seek`, dans l'ordre.
  final seeks = <Duration>[];

  @override
  final state = const PlayerState(
    playing: true,
    duration: Duration(minutes: 90),
  );

  @override
  final PlayerStream stream = _NoStreams();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    if (invocation.memberName == #seek) {
      seeks.add(invocation.positionalArguments.first as Duration);
    }
    return Future<void>.value();
  }
}

class _NoStreams implements PlayerStream {
  @override
  dynamic noSuchMethod(Invocation invocation) => const Stream<Never>.empty();
}

void main() {
  late _FakePlayer player;

  setUp(() => player = _FakePlayer());

  /// Dans l'app entière : ses réglages de navigation (télécommande) comptent.
  Future<void> pumpControls(WidgetTester tester, {bool volume = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        child: CouchPlayApp(
          home: Scaffold(
            body: PlayerControls(
              player: player,
              title: 'Horizon',
              fill: false,
              onToggleFill: () {},
              fullscreen: null,
              onToggleFullscreen: () {},
              onExit: () {},
              volume: volume,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

  testWidgets('télécommande : OK, ↓ vers les boutons, retour sur l\'image', (
    tester,
  ) async {
    await pumpControls(tester);
    expect(focused(), 'vidéo');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(player.calls, [#playOrPause]);

    // ↓ mène au bouton lecture ; OK l'active.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(focused(), 'lecture');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(player.calls, [#playOrPause, #playOrPause]);

    // Contrôles masqués : le focus revient sur l'image, ← les réaffiche,
    // puis recule.
    await tester.pump(const Duration(seconds: 4));
    expect(focused(), 'vidéo');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(player.calls.last, #seek);
  });

  testWidgets('télécommande : ⏪ ⏩ sautent de 10 s, où que soit le focus', (
    tester,
  ) async {
    await pumpControls(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
    // Sur un bouton aussi.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(focused(), 'lecture');
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaRewind);
    // Position fixe du faux lecteur (0) : ⏪ s'arrête au début.
    expect(player.seeks, [const Duration(seconds: 10), Duration.zero]);

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
    expect(player.calls, containsAllInOrder([#pause, #play]));
  });

  testWidgets('← → sur l\'image : contrôles masqués, le premier appui les '
      'affiche sans bouger la vidéo', (tester) async {
    await pumpControls(tester);
    await tester.pump(const Duration(seconds: 4));
    double opacity() => tester
        .widget<AnimatedOpacity>(
          find
              .descendant(
                of: find.byType(PlayerControls),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;
    expect(opacity(), 0, reason: 'contrôles masqués');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(player.seeks, isEmpty);
    await tester.pump();
    expect(opacity(), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(player.seeks, [const Duration(seconds: 10)]);

    // Maintenue, contrôles masqués : le premier événement affiche, les
    // répétitions sautent.
    await tester.pump(const Duration(seconds: 4));
    player.seeks.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(player.seeks, [const Duration(seconds: 10)]);
  });

  testWidgets('télécommande : ↑ ↓ traversent la barre de progression', (
    tester,
  ) async {
    await pumpControls(tester);
    String? button() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<IconButton>()
        ?.tooltip;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(button(), 'Pause');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(button(), 'Avancer de 10 s');
    // Le curseur de progression, juste au-dessus, puis la barre du haut, sans
    // avancer dans la vidéo.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<Slider>(),
      isNotNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(button(), 'Retour');
    expect(player.calls, isNot(contains(#seek)));
  });

  testWidgets(
    'clavier d\'ordinateur : ↑ règle le volume, sans quitter l\'image',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await pumpControls(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        expect(focused(), 'vidéo');
        expect(player.calls, [#setVolume]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('retour Android : ferme le lecteur seul, pas la fiche dessous', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CouchPlayApp(home: Scaffold(body: Text('Accueil'))),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Fiche')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          body: PlayerControls(
            player: player,
            title: 'Horizon',
            fill: false,
            onToggleFill: () {},
            fullscreen: null,
            onToggleFullscreen: () {},
            onExit: () => Navigator.maybePop(context),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Android : la touche passe d'abord par l'app, puis par le retour système.
    // Simulée en « web » : le simulateur n'a pas de code Android pour elle.
    await tester.sendKeyEvent(
      LogicalKeyboardKey.goBack,
      platform: 'web',
      physicalKey: PhysicalKeyboardKey.browserBack,
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();

    expect(find.byType(PlayerControls), findsNothing);
    expect(find.text('Fiche'), findsOneWidget);
  });

  testWidgets('TV : pas de volume, la télécommande règle celui de la TV', (
    tester,
  ) async {
    await pumpControls(tester, volume: false);
    expect(find.byTooltip('Couper le son'), findsNothing);
    expect(find.byType(Slider), findsOneWidget, reason: 'la progression seule');
  });
}
