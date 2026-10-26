import 'package:couchplay/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('le thème suit le système par défaut', () async {
    final store = await SettingsStore.open();
    expect(store.theme, ThemePreference.system);
    expect(store.theme.themeMode, ThemeMode.system);
  });

  test('le thème choisi survit à une réouverture', () async {
    await (await SettingsStore.open()).setTheme(ThemePreference.dark);
    final reopened = await SettingsStore.open();
    expect(reopened.theme, ThemePreference.dark);
    expect(reopened.theme.themeMode, ThemeMode.dark);
  });

  test('une valeur inconnue en stockage revient au thème système', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({'theme': 'violet'});
    expect((await SettingsStore.open()).theme, ThemePreference.system);
  });

  test('le provider applique et enregistre le choix', () async {
    final store = await SettingsStore.open();
    final container = ProviderContainer.test(
      overrides: [settingsStoreProvider.overrideWithValue(store)],
    );
    expect(container.read(themePreferenceProvider), ThemePreference.system);

    await container
        .read(themePreferenceProvider.notifier)
        .set(ThemePreference.light);

    expect(container.read(themePreferenceProvider), ThemePreference.light);
    expect((await SettingsStore.open()).theme, ThemePreference.light);
  });
}
