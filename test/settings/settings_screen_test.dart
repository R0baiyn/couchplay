import 'package:couchplay/accounts/app_settings.dart';
import 'package:couchplay/settings/settings_screen.dart';
import 'package:couchplay/television.dart';
import 'package:couchplay/update/updater.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpSettings(WidgetTester tester, {bool tv = false}) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVersionProvider.overrideWithValue('0.1.0'),
            televisionProvider.overrideWithValue(tv),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );

  testWidgets('la version de l\'app est affichée', (tester) async {
    await pumpSettings(tester);
    await tester.scrollUntilVisible(find.text('Version 0.1.0'), 100);
    expect(find.text('Version 0.1.0'), findsOneWidget);
  });

  testWidgets('l\'interrupteur « Mode debug » bascule le réglage', (
    tester,
  ) async {
    await pumpSettings(tester);
    final context = tester.element(find.byType(SettingsScreen));
    final container = ProviderScope.containerOf(context);
    expect(container.read(appSettingsProvider).debug, isFalse);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings.debug')),
      100,
    );
    await tester.tap(find.byKey(const ValueKey('settings.debug')));
    await tester.pump();
    expect(container.read(appSettingsProvider).debug, isTrue);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('settings.debug')))
          .value,
      true,
    );
  });

  testWidgets('les interrupteurs de téléchargement changent les réglages', (
    tester,
  ) async {
    await pumpSettings(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(container.read(appSettingsProvider).wifiOnly, isTrue);
    expect(container.read(appSettingsProvider).deleteWatched, isFalse);

    await tester.tap(find.byKey(const ValueKey('settings.wifiOnly')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings.deleteWatched')));
    await tester.pump();

    expect(container.read(appSettingsProvider).wifiOnly, isFalse);
    expect(container.read(appSettingsProvider).deleteWatched, isTrue);
  });

  testWidgets('Android TV : pas d’interrupteur de téléchargement', (
    tester,
  ) async {
    await pumpSettings(tester, tv: true);
    expect(find.byKey(const ValueKey('settings.wifiOnly')), findsNothing);
    expect(find.byKey(const ValueKey('settings.deleteWatched')), findsNothing);
    expect(find.byKey(const ValueKey('settings.debug')), findsOneWidget);
  });
}
