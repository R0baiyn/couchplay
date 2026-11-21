import 'dart:ffi';

import 'package:couchplay/update/android_installer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('androidAssetSuffixFor', () {
    test('téléphone 64 bits dont l\'app tourne en armv7 : arm64', () {
      expect(
        androidAssetSuffixFor(['arm64-v8a'], Abi.androidArm),
        '-android-arm64.apk',
      );
    });

    test('TV 32 bits (aucune architecture 64 bits) : armv7', () {
      expect(androidAssetSuffixFor([], Abi.androidArm), '-android-armv7.apk');
    });

    test('émulateur x86_64 : aucun APK publié', () {
      expect(androidAssetSuffixFor(['x86_64'], Abi.androidX64), isNull);
    });

    test('liste inconnue (canal muet) sur un processus arm64 : arm64', () {
      expect(androidAssetSuffixFor([], Abi.androidArm64), '-android-arm64.apk');
    });
  });

  group('deviceAssetSuffix', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('couchplay/update');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('lit les architectures 64 bits par le canal', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return ['arm64-v8a'];
      });
      expect(await AndroidInstaller.deviceAssetSuffix(), '-android-arm64.apk');
      expect(calls, ['supported64BitAbis']);
    });

    test("erreur du canal : l'architecture du processus seule", () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'x'),
      );
      expect(
        await AndroidInstaller.deviceAssetSuffix(),
        androidAssetSuffix(Abi.current()),
      );
    });

    test("canal absent : l'architecture du processus seule", () async {
      expect(
        await AndroidInstaller.deviceAssetSuffix(),
        androidAssetSuffix(Abi.current()),
      );
    });
  });
}
