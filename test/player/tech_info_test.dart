import 'dart:io';

import 'package:couchplay/player/player_controls.dart';
import 'package:couchplay/player/tech_info.dart';
import 'package:couchplay/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

class _FakePlayer implements Player {
  _FakePlayer(this.state);

  @override
  final PlayerState state;

  @override
  final PlayerStream stream = _NoStreams();

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _NoStreams implements PlayerStream {
  @override
  dynamic noSuchMethod(Invocation invocation) => const Stream<Never>.empty();
}

const _stream = PlayerState(
  width: 1920,
  height: 1080,
  tracks: Tracks(
    video: [
      VideoTrack('auto', null, null),
      VideoTrack('1', null, null, codec: 'h264', bitrate: 3200000),
    ],
    audio: [
      AudioTrack('auto', null, null),
      AudioTrack('1', null, null, codec: 'aac', bitrate: 192000),
    ],
  ),
  audioParams: AudioParams(hrChannels: '5.1'),
);

void main() {
  late File file;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('couchplay_tech');
    addTearDown(() => dir.deleteSync(recursive: true));
    file = File('${dir.path}${Platform.pathSeparator}settings.json')
      ..writeAsStringSync('{"debug": true}');
  });

  test('codecs, canaux et débits du flux', () {
    expect(techInfo(_stream), [
      '1920 × 1080 · h264 · 3,2 Mb/s',
      'aac · 5.1 · 192 kb/s',
    ]);
  });

  test('info inconnue omise, rien du tout : aucune ligne', () {
    expect(techInfo(const PlayerState()), isEmpty);
    const bare = PlayerState(
      width: 1280,
      height: 720,
      tracks: Tracks(video: [VideoTrack('1', null, null, bitrate: 0)]),
    );
    expect(techInfo(bare), ['1280 × 720']);
  });

  Future<void> pumpControls(WidgetTester tester, {required bool debug}) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            if (debug) appSettingsFileProvider.overrideWithValue(file),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PlayerControls(
                player: _FakePlayer(_stream),
                title: 'Horizon',
                fill: false,
                onToggleFill: () {},
                fullscreen: null,
                onToggleFullscreen: () {},
                onExit: () {},
              ),
            ),
          ),
        ),
      );

  testWidgets('option décochée : aucune info, pas même la résolution', (
    tester,
  ) async {
    await pumpControls(tester, debug: false);
    expect(find.textContaining('1920'), findsNothing);
    expect(find.textContaining('h264'), findsNothing);
  });

  testWidgets('option cochée : résolution et codecs visibles', (tester) async {
    await pumpControls(tester, debug: true);
    expect(find.textContaining('1920 × 1080 · h264'), findsOneWidget);
    expect(find.textContaining('aac · 5.1'), findsOneWidget);
  });
}
