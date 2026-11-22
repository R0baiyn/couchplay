import 'package:couchplay/orientation.dart';
import 'package:couchplay/player/mobile_fullscreen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _portrait = ['DeviceOrientation.portraitUp'];
const _landscape = [
  'DeviceOrientation.landscapeLeft',
  'DeviceOrientation.landscapeRight',
];

void main() {
  group('isPhone', () {
    test('Android, petit côté sous 600 dp : téléphone, dans les deux sens', () {
      expect(isPhone(const Size(360, 800), android: true), isTrue);
      expect(isPhone(const Size(800, 360), android: true), isTrue);
      expect(isPhone(const Size(599, 1300), android: true), isTrue);
    });

    test('tablette (600 dp et plus), TV, PC, taille inconnue : non', () {
      expect(isPhone(const Size(600, 960), android: true), isFalse);
      expect(isPhone(const Size(1280, 800), android: true), isFalse);
      expect(
        isPhone(const Size(960, 540), android: true, television: true),
        isFalse,
      );
      // Fenêtre PC étroite : jamais de contrainte.
      expect(isPhone(const Size(360, 800), android: false), isFalse);
      // Taille pas encore connue : ne jamais bloquer une tablette.
      expect(isPhone(Size.zero, android: true), isFalse);
    });
  });

  group('allowedOrientations', () {
    test(
      'téléphone : portrait seul hors du lecteur, paysage dans le lecteur',
      () {
        expect(allowedOrientations(phone: true, player: false), [
          DeviceOrientation.portraitUp,
        ]);
        expect(allowedOrientations(phone: true, player: true), [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      },
    );

    test('tablette et TV : aucune contrainte hors du lecteur, paysage dedans '
        '(comme avant)', () {
      expect(allowedOrientations(phone: false, player: false), isEmpty);
      expect(allowedOrientations(phone: false, player: true), [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    });
  });

  group('MobileFullscreen', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    List<Object?> orientations() => [
      for (final c in calls)
        if (c.method == 'SystemChrome.setPreferredOrientations') c.arguments,
    ];

    for (final phone in [true, false]) {
      testWidgets('${phone ? 'téléphone' : 'tablette'} : paysage et plein '
          'écran à l\'entrée, ${phone ? 'portrait' : 'rotation libre'} à la '
          'sortie', (tester) async {
        await tester.pumpWidget(
          MobileFullscreen(phone: phone, child: const SizedBox()),
        );
        expect(orientations(), [_landscape]);
        expect(
          calls.map((c) => c.method),
          contains('SystemChrome.setEnabledSystemUIMode'),
        );

        calls.clear();
        await tester.pumpWidget(const SizedBox());
        expect(orientations(), [phone ? _portrait : <String>[]]);
        // Mode manuel, barres du système revenues.
        expect(
          calls.map((c) => c.method),
          contains('SystemChrome.setEnabledSystemUIOverlays'),
        );
      });
    }
  });
}
