import 'package:couchplay/settings/settings.dart';
import 'package:couchplay/settings/settings_screen.dart';
import 'package:couchplay/update/updater.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = await tester.runAsync(SettingsStore.open);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store!),
          appVersionProvider.overrideWithValue('0.1.0'),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    return ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
  }

  testWidgets('la version de l\'app est affichée', (tester) async {
    await pumpSettings(tester);
    await tester.scrollUntilVisible(find.text('Version 0.1.0'), 100);
    expect(find.text('Version 0.1.0'), findsOneWidget);
  });

  testWidgets('le thème « Comme le système » est coché par défaut', (
    tester,
  ) async {
    await pumpSettings(tester);
    final group = tester.widget<RadioGroup<ThemePreference>>(
      find.byType(RadioGroup<ThemePreference>),
    );
    expect(group.groupValue, ThemePreference.system);
  });

  testWidgets('choisir « Sombre » l\'applique et l\'enregistre', (
    tester,
  ) async {
    final container = await pumpSettings(tester);

    await tester.tap(find.text('Sombre'));
    await tester.pumpAndSettle();

    expect(container.read(themePreferenceProvider), ThemePreference.dark);
    final reopened = await tester.runAsync(SettingsStore.open);
    expect(reopened!.theme, ThemePreference.dark);
  });

  testWidgets('le thème se choisit au clavier', (tester) async {
    final container = await pumpSettings(tester);

    // Comptes a le focus ; Tab passe à Abonnement, Catalogue, puis entre
    // dans le groupe du thème, où les flèches passent d'un choix à l'autre.
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(container.read(themePreferenceProvider), ThemePreference.light);
  });
}
