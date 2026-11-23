import 'dart:async';

import 'package:couchplay/player/audio_focus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('couchplay/audio');

  late List<String> calls;
  late bool granted;
  late List<String> logs;
  late StreamController<bool> playing;
  late int pauses;
  final printer = debugPrint;

  setUp(() {
    calls = [];
    granted = true;
    logs = [];
    pauses = 0;
    playing = StreamController<bool>.broadcast();
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'request' ? granted : null;
    });
  });

  tearDown(() async {
    debugPrint = printer;
    messenger.setMockMethodCallHandler(channel, null);
    await playing.close();
  });

  AudioFocus focus({bool android = true}) => AudioFocus(
    playing: playing.stream,
    pause: () async => pauses++,
    android: android,
  );

  /// Appel venu de `MainActivity.kt`.
  Future<void> fromAndroid(String reason) => messenger.handlePlatformMessage(
    channel.name,
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('interrupted', reason),
    ),
    (_) {},
  );

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test(
    'demandé au passage en lecture, une fois tant qu\'il est tenu',
    () async {
      final audio = focus();
      playing
        ..add(true)
        ..add(false)
        ..add(true);
      await flush();
      expect(calls, ['request']);
      await audio.dispose();
    },
  );

  test(
    'son pris par une autre app : pause, journal, redemandé à la reprise',
    () async {
      final audio = focus();
      playing.add(true);
      await flush();
      await fromAndroid('focus');
      expect(pauses, 1);
      expect(
        logs.last,
        contains('Lecture : pause, son pris par une autre app'),
      );
      playing
        ..add(false)
        ..add(true);
      await flush();
      expect(calls, ['request', 'request']);
      await audio.dispose();
    },
  );

  test('casque débranché : pause et journal', () async {
    final audio = focus();
    playing.add(true);
    await flush();
    await fromAndroid('noisy');
    expect(pauses, 1);
    expect(logs.last, contains('Lecture : pause, casque débranché'));
    await audio.dispose();
  });

  test('focus refusé : pause', () async {
    granted = false;
    final audio = focus();
    playing.add(true);
    await flush();
    expect(pauses, 1);
    expect(logs.last, contains('Lecture : pause, son pris par une autre app'));
    await audio.dispose();
  });

  test('rendu à la fermeture ; plus de pause ensuite', () async {
    final audio = focus();
    playing.add(true);
    await flush();
    await audio.dispose();
    expect(calls, ['request', 'abandon']);
    await fromAndroid('focus');
    expect(pauses, 0);
  });

  test('hors Android : aucun appel au canal', () async {
    final audio = focus(android: false);
    playing.add(true);
    await flush();
    await audio.dispose();
    expect(calls, isEmpty);
  });
}
