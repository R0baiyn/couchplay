import 'package:couchplay/focus_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _list(Axis axis, ScrollController controller) {
  return MaterialApp(
    home: Scaffold(
      body: SmoothFocusGroup(
        child: ListView(
          controller: controller,
          scrollDirection: axis,
          children: [
            for (var i = 0; i < 20; i++)
              SizedBox(
                width: 200,
                height: 200,
                child: TextButton(onPressed: () {}, child: Text('item $i')),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _checkAnimated(
  WidgetTester tester,
  Axis axis,
  LogicalKeyboardKey key,
) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(_list(axis, controller));
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  // Avance jusqu'à ce que le focus sorte de l'écran.
  for (var i = 0; i < 6; i++) {
    await tester.sendKeyEvent(key);
    await tester.pump(focusScrollDuration + const Duration(milliseconds: 50));
  }
  final before = controller.offset;
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(focusScrollDuration ~/ 4);
  final middle = controller.offset;
  await tester.pump(focusScrollDuration);
  final after = controller.offset;
  expect(middle, greaterThan(before), reason: 'le défilement a commencé');
  expect(middle, lessThan(after), reason: 'pas encore arrivé : animé');
}

void main() {
  testWidgets('↓ vers une ligne cachée défile en animation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _checkAnimated(tester, Axis.vertical, LogicalKeyboardKey.arrowDown);
  });

  testWidgets('→ vers une affiche cachée défile en animation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _checkAnimated(
      tester,
      Axis.horizontal,
      LogicalKeyboardKey.arrowRight,
    );
  });
}
