import 'package:couchplay/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('toujours en thème sombre, même si le système est clair', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      const ProviderScope(child: CouchPlayApp(home: SizedBox())),
    );

    final context = tester.element(find.byType(SizedBox));
    expect(Theme.of(context).brightness, Brightness.dark);
  });
}
