import 'dart:io';

import 'package:couchplay/accounts/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('couchplay_settings');
    file = File('${dir.path}${Platform.pathSeparator}settings.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [appSettingsFileProvider.overrideWithValue(file)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('fichier absent : debug désactivé', () {
    expect(container().read(appSettingsProvider).debug, isFalse);
  });

  test('écrit puis relu : debug activé', () async {
    await container().read(appSettingsProvider.notifier).setDebug(true);
    expect(container().read(appSettingsProvider).debug, isTrue);
  });

  test('Wi-Fi seulement : activé par défaut, gardé avec debug', () async {
    expect(container().read(appSettingsProvider).wifiOnly, isTrue);
    final c = container();
    await c.read(appSettingsProvider.notifier).setWifiOnly(false);
    await c.read(appSettingsProvider.notifier).setDebug(true);
    final read = container().read(appSettingsProvider);
    expect((read.wifiOnly, read.debug), (false, true));
  });

  test(
    'Effacer une fois vu : désactivé par défaut, gardé avec les autres',
    () async {
      expect(container().read(appSettingsProvider).deleteWatched, isFalse);
      final c = container();
      await c.read(appSettingsProvider.notifier).setDeleteWatched(true);
      await c.read(appSettingsProvider.notifier).setWifiOnly(false);
      final read = container().read(appSettingsProvider);
      expect((read.deleteWatched, read.wifiOnly), (true, false));
    },
  );

  test('fichier illisible : debug désactivé', () {
    file.writeAsStringSync('{pas du json');
    expect(container().read(appSettingsProvider).debug, isFalse);
  });

  test('sans fichier injecté : désactivé, rien n\'est écrit', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).setDebug(true);
    expect(c.read(appSettingsProvider).debug, isTrue);
    expect(file.existsSync(), isFalse);
  });
}
