import 'package:couchplay/accounts/app_settings.dart';
import 'package:couchplay/settings/advanced_settings_screen.dart';
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
    expect(find.byKey(const ValueKey('settings.advanced')), findsOneWidget);
  });

  // D-069 : les outils d'essai et de dépannage sont dans « Réglages avancés ».
  for (final tv in [false, true]) {
    testWidgets('« Réglages avancés » ouvre leur écran (TV : $tv)', (
      tester,
    ) async {
      await pumpSettings(tester, tv: tv);
      for (final key in [
        'settings.directVideo',
        'settings.debug',
        'settings.journal',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
      }
      final advanced = find.byKey(const ValueKey('settings.advanced'));
      await tester.scrollUntilVisible(advanced, 100);
      expect(tester.widget<ListTile>(advanced).subtitle, isNull);

      await tester.tap(advanced);
      await tester.pumpAndSettle();
      expect(find.byType(AdvancedSettingsScreen), findsOneWidget);
      expect(find.text('Réglages avancés'), findsWidgets);
    });
  }

  testWidgets('« Réglages avancés » est juste avant « Version »', (
    tester,
  ) async {
    await pumpSettings(tester);
    final advanced = find.byKey(const ValueKey('settings.advanced'));
    await tester.scrollUntilVisible(advanced, 100);
    final version = find.byKey(const ValueKey('settings.version'));
    await tester.scrollUntilVisible(version, 100);
    expect(
      tester.getTopLeft(advanced).dy,
      lessThan(tester.getTopLeft(version).dy),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('settings.deleteWatched')))
          .dy,
      lessThan(tester.getTopLeft(advanced).dy),
    );
  });
}
