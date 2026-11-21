import 'dart:ffi';
import 'dart:io';

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

    test('x86_64 qui traduit l\'arm64 (émulateur, Chromebook) : aucun', () {
      expect(
        androidAssetSuffixFor(['x86_64', 'arm64-v8a'], Abi.androidX64),
        isNull,
      );
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
      expect(
        await AndroidInstaller.deviceAssetSuffix(current: Abi.androidArm),
        '-android-arm64.apk',
      );
      expect(calls, ['supported64BitAbis']);
    });

    test("erreur du canal : l'architecture du processus seule", () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'x'),
      );
      expect(
        await AndroidInstaller.deviceAssetSuffix(current: Abi.androidArm),
        '-android-armv7.apk',
      );
    });

    test("canal absent : l'architecture du processus seule", () async {
      expect(
        await AndroidInstaller.deviceAssetSuffix(current: Abi.androidArm64),
        '-android-arm64.apk',
      );
    });
  });

  group('installPending', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('couchplay/update');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('couchplay_apk_');
      File('${dir.path}/version').writeAsStringSync('9.9.9');
      File('${dir.path}/couchplay.apk').writeAsStringSync('apk');
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test(
      'installation refusée par le canal : place nette, pas de levée',
      () async {
        messenger.setMockMethodCallHandler(
          channel,
          (call) async => throw PlatformException(code: 'no_installer'),
        );
        final installer = AndroidInstaller(assetSuffix: '', workDir: dir);

        expect(await installer.installPending('1.0.0'), isFalse);
        expect(dir.existsSync(), isFalse);
      },
    );

    test('installation lancée : le dossier reste', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      final installer = AndroidInstaller(assetSuffix: '', workDir: dir);

      expect(await installer.installPending('1.0.0'), isTrue);
      expect(dir.existsSync(), isTrue);
    });
  });
}
