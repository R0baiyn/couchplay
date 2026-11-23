import 'package:couchplay/accounts/app_settings.dart';
import 'package:couchplay/settings/advanced_settings_screen.dart';
import 'package:couchplay/settings/journal_screen.dart';
import 'package:couchplay/television.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpAdvanced(WidgetTester tester, {bool tv = false}) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            televisionProvider.overrideWithValue(tv),
            journalLinesProvider.overrideWith(
              (ref) async => ['ligne du journal'],
            ),
          ],
          child: const MaterialApp(home: AdvancedSettingsScreen()),
        ),
      );

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(AdvancedSettingsScreen)),
      );

  testWidgets('l\'interrupteur « Mode debug » bascule le réglage', (
    tester,
  ) async {
    await pumpAdvanced(tester);
    final container = containerOf(tester);
    expect(container.read(appSettingsProvider).debug, isFalse);

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

  testWidgets('TV : « Lecture directe » éteinte, bascule le réglage', (
    tester,
  ) async {
    await pumpAdvanced(tester, tv: true);
    final tile = find.byKey(const ValueKey('settings.directVideo'));
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(find.text("Si l'image saccade (après relance)"), findsOneWidget);

    await tester.tap(tile);
    await tester.pump();
    expect(containerOf(tester).read(appSettingsProvider).directVideo, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
  });

  testWidgets('hors TV : pas de « Lecture directe »', (tester) async {
    await pumpAdvanced(tester);
    expect(find.byKey(const ValueKey('settings.directVideo')), findsNothing);
  });

  testWidgets('TV : Lecture directe, Mode debug, Journal, dans cet ordre', (
    tester,
  ) async {
    await pumpAdvanced(tester, tv: true);
    final tops = [
      'settings.directVideo',
      'settings.debug',
      'settings.journal',
    ].map((k) => tester.getTopLeft(find.byKey(ValueKey(k))).dy).toList();
    expect(tops, orderedEquals([...tops]..sort()));
  });

  for (final tv in [false, true]) {
    testWidgets('« Journal » ouvre le journal (TV : $tv)', (tester) async {
      await pumpAdvanced(tester, tv: tv);
      await tester.tap(find.byKey(const ValueKey('settings.journal')));
      await tester.pumpAndSettle();
      expect(find.byType(JournalScreen), findsOneWidget);
      expect(find.text('ligne du journal'), findsOneWidget);
    });
  }
}
