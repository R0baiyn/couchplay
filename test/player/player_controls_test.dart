import 'package:couchplay/player/player_controls.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// Lecteur sans libmpv : en lecture, aucun flux, chaque appel compté.
class _FakePlayer implements Player {
  final calls = <Symbol>[];

  @override
  final state = const PlayerState(playing: true);

  @override
  final PlayerStream stream = _NoStreams();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
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

  Future<void> pumpControls(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PlayerControls(
          player: player,
          title: 'Libre',
          fill: false,
          onToggleFill: () {},
          fullscreen: null,
          onToggleFullscreen: () {},
          onExit: () {},
        ),
      ),
    ),
  );

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

    // Contrôles masqués : le focus revient sur l'image, ← recule.
    await tester.pump(const Duration(seconds: 4));
    expect(focused(), 'vidéo');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(player.calls.last, #seek);
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
}
