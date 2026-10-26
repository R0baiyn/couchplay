import 'package:couchplay/app.dart';
import 'package:couchplay/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  Future<SettingsStore> storeWith(Map<String, Object> data) {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(data);
    return SettingsStore.open();
  }

  Future<ThemeMode?> pumpApp(WidgetTester tester, SettingsStore store) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
        child: const CouchPlayApp(home: SizedBox()),
      ),
    );
    return tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode;
  }

  testWidgets('suit le thème du système par défaut, clair et sombre fournis', (
    tester,
  ) async {
    final store = await tester.runAsync(() => storeWith({}));
    expect(await pumpApp(tester, store!), ThemeMode.system);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.brightness, Brightness.light);
    expect(app.darkTheme!.brightness, Brightness.dark);
  });

  testWidgets('applique le thème enregistré, puis un nouveau choix', (
    tester,
  ) async {
    final store = await tester.runAsync(() => storeWith({'theme': 'dark'}));
    expect(await pumpApp(tester, store!), ThemeMode.dark);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CouchPlayApp)),
    );
    await tester.runAsync(
      () => container
          .read(themePreferenceProvider.notifier)
          .set(ThemePreference.light),
    );
    await tester.pump();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
  });
}
