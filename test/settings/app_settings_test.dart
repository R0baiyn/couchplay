import 'dart:io';

import 'package:couchplay/settings/app_settings.dart';
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
