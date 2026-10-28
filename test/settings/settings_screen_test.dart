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
}
