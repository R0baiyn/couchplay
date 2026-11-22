import 'package:couchplay/app.dart';
import 'package:couchplay/player/player_tracks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// Lecteur sans libmpv : deux pistes audio, deux de sous-titres ; chaque
/// appel retenu.
class _FakePlayer implements Player {
  final calls = <Invocation>[];

  @override
  final state = const PlayerState(
    tracks: Tracks(
      audio: [AudioTrack('1', null, 'fre'), AudioTrack('2', 'Bip', 'eng')],
      subtitle: [
        SubtitleTrack('3', null, 'fre'),
        SubtitleTrack('4', null, 'eng'),
      ],
    ),
  );

  @override
  final PlayerStream stream = _NoStreams();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
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

  /// Dans l'app entière, sur Android : navigation de télécommande.
  Future<void> pumpMenu(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: CouchPlayApp(
          home: Scaffold(
            body: Center(
              child: TracksMenu(player: player, onOpened: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Le focus est sur l'entrée [key] ou dans elle.
  bool focusIn(Key key) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    if (context.widget.key == key) return true;
    var found = false;
    context.visitAncestorElements((e) => !(found = e.widget.key == key));
    return found;
  }

  /// Ouvre le menu de [icon] à la télécommande, descend jusqu'à [item] et
  /// le choisit par OK.
  Future<void> chooseByRemote(
    WidgetTester tester,
    IconData icon,
    Key item,
  ) async {
    Focus.of(tester.element(find.byIcon(icon))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    for (var i = 0; i < 10 && !focusIn(item); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    expect(focusIn(item), isTrue, reason: 'entrée atteinte par ↓');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
  }

  Invocation? call(Symbol name) =>
      player.calls.where((c) => c.memberName == name).lastOrNull;

  testWidgets('télécommande : OK sur une piste de sous-titres la choisit', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpMenu(tester);
      await chooseByRemote(
        tester,
        Icons.subtitles,
        const ValueKey('player.subtitleTrack.3'),
      );
      final chosen = call(#setSubtitleTrack);
      expect(chosen, isNotNull, reason: 'OK sans effet');
      expect((chosen!.positionalArguments.first as SubtitleTrack).id, '3');
      expect(find.byKey(const ValueKey('player.subtitleOff')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('télécommande : OK sur « Désactivés » coupe les sous-titres', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpMenu(tester);
      await chooseByRemote(
        tester,
        Icons.subtitles,
        const ValueKey('player.subtitleOff'),
      );
      final chosen = call(#setSubtitleTrack);
      expect(chosen, isNotNull, reason: 'OK sans effet');
      expect((chosen!.positionalArguments.first as SubtitleTrack).id, 'no');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('télécommande : OK sur une piste audio la choisit', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpMenu(tester);
      await chooseByRemote(
        tester,
        Icons.audiotrack,
        const ValueKey('player.audioTrack.2'),
      );
      final chosen = call(#setAudioTrack);
      expect(chosen, isNotNull, reason: 'OK sans effet');
      expect((chosen!.positionalArguments.first as AudioTrack).id, '2');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
