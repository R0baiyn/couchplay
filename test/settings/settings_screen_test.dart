import 'package:couchplay/settings/app_settings.dart';
import 'package:couchplay/settings/settings_screen.dart';
import 'package:couchplay/update/updater.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpSettings(WidgetTester tester) => tester.pumpWidget(
    ProviderScope(
      overrides: [appVersionProvider.overrideWithValue('0.1.0')],
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

    await tester.scrollUntilVisible(find.text('Mode debug'), 100);
    await tester.tap(find.text('Mode debug'));
    await tester.pump();
    expect(container.read(appSettingsProvider).debug, isTrue);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      true,
    );
  });
}
