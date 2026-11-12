import 'package:couchplay/app.dart';
import 'package:couchplay/focus_ring.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final first = find.widgetWithText(FilledButton, 'Un');
  final second = find.widgetWithText(FilledButton, 'Deux');

  Future<void> pumpApp(WidgetTester tester, Widget body) => tester.pumpWidget(
    ProviderScope(
      child: CouchPlayApp(home: Scaffold(body: body)),
    ),
  );

  Future<void> pumpButtons(WidgetTester tester) => pumpApp(
    tester,
    Column(
      children: [
        FilledButton(onPressed: () {}, child: const Text('Un')),
        FilledButton(onPressed: () {}, child: const Text('Deux')),
      ],
    ),
  );

  /// Le contour que le bouton dessine.
  BorderSide sideOf(WidgetTester tester, Finder button) {
    final material = tester.widget<Material>(
      find.descendant(of: button, matching: find.byType(Material)).first,
    );
    return (material.shape! as OutlinedBorder).side;
  }

  testWidgets('le bouton qui a le focus clavier porte l’anneau, pas l’autre', (
    tester,
  ) async {
    await pumpButtons(tester);
    final size = tester.getSize(first);
    expect(sideOf(tester, first), BorderSide.none);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(sideOf(tester, first), focusRing);
    expect(focusRing.color, Colors.white);
    expect(focusRing.width, 3);
    expect(sideOf(tester, second), BorderSide.none);
    // L'anneau ne déplace rien.
    expect(tester.getSize(first), size);
  });

  testWidgets('plus d’anneau dès qu’on touche l’écran', (tester) async {
    await pumpButtons(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(sideOf(tester, first), focusRing);

    // Le toucher ne prend pas le focus : « Un » le garde, sans anneau.
    await tester.tap(second);
    await tester.pumpAndSettle();

    expect(sideOf(tester, first), BorderSide.none);
    expect(sideOf(tester, second), BorderSide.none);
  });

  testWidgets('pas d’anneau après un clic de souris', (tester) async {
    await pumpButtons(tester);

    await tester.tap(first, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(sideOf(tester, first), BorderSide.none);
    expect(sideOf(tester, second), BorderSide.none);
  });

  testWidgets('FocusRing entoure toute la tuile dont il est le titre', (
    tester,
  ) async {
    await pumpApp(
      tester,
      ListTile(
        title: const FocusRing(child: Text('Comptes')),
        subtitle: const Text('Ajouter, modifier'),
        onTap: () {},
      ),
    );
    final ring = find.byType(FocusRing);
    final size = tester.getSize(find.byType(ListTile));
    final tile =
        (tester.getTopLeft(find.byType(ListTile)) - tester.getTopLeft(ring)) &
        size;
    final painted = paints
      ..rrect(
        rrect: RRect.fromRectAndRadius(
          tile.deflate(focusRing.width / 2),
          const Radius.circular(8),
        ),
        color: Colors.white,
        strokeWidth: 3,
      );
    expect(tester.renderObject(ring), isNot(painted));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(tester.renderObject(ring), painted);
    expect(tester.getSize(find.byType(ListTile)), size);

    await tester.tapAt(const Offset(400, 500));
    await tester.pumpAndSettle();
    expect(tester.renderObject(ring), isNot(painted));
  });
}
