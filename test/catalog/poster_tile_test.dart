import 'package:couchplay/catalog/poster_grid.dart';
import 'package:couchplay/confirm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var taps = 0;
  var menus = 0;

  Future<void> pumpTile(WidgetTester tester, {required bool withMenu}) async {
    taps = menus = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 170,
            child: PosterTile(
              title: 'Horizon',
              imageUrl: null,
              onTap: () => taps++,
              onMenu: withMenu ? () => menus++ : null,
            ),
          ),
        ),
      ),
    );
    // Tab : le clavier donne le focus à la tuile.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }

  Future<void> hold(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyRepeatEvent(key);
    }
    await tester.sendKeyUpEvent(key);
    await tester.pump();
  }

  testWidgets('OK maintenu : le menu s’ouvre une fois, la fiche pas', (
    tester,
  ) async {
    await pumpTile(tester, withMenu: true);
    await hold(tester, LogicalKeyboardKey.select);
    expect((menus, taps), (1, 0));
  });

  testWidgets('OK appuyé : ouvre la fiche, pas le menu', (tester) async {
    await pumpTile(tester, withMenu: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect((menus, taps), (0, 1));
  });

  testWidgets('OK maintenu répété en appuis successifs : le menu une fois, '
      'la fiche pas ; un appui court ensuite l’ouvre', (tester) async {
    await pumpTile(tester, withMenu: true);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 33));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect((menus, taps), (1, 0));

    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect((menus, taps), (1, 1));
  });

  testWidgets('touche Menu : ouvre le menu', (tester) async {
    await pumpTile(tester, withMenu: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump();
    expect((menus, taps), (1, 0));
  });

  testWidgets('sans menu, OK maintenu ne fait pas plus qu’un appui court', (
    tester,
  ) async {
    await pumpTile(tester, withMenu: false);
    await hold(tester, LogicalKeyboardKey.select);
    expect((menus, taps), (0, 1));
  });

  // Séquence relevée sur l'émulateur TV (clavier USB maintenu, puis getevent
  // sur le clavier de la fenêtre) : un appui, des répétitions, un relâchement,
  // sans paires appui/relâchement. Le menu s'ouvre pendant le maintien et ne
  // reçoit rien de lui ; « Retirer » a le focus, le cas le plus dangereux.
  group('maintien de OK sur une tuile à menu', () {
    late bool? answer;

    Future<void> pumpMenuTile(
      WidgetTester tester, {
      bool cancelFirst = false,
    }) async {
      answer = null;
      taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: SizedBox(
                width: 170,
                child: PosterTile(
                  title: 'Horizon',
                  imageUrl: null,
                  onTap: () => taps++,
                  onMenu: () async => answer = await confirm(
                    context,
                    title: 'Horizon',
                    content: 'Retirer ?',
                    action: 'Retirer',
                    focusCancel: cancelFirst,
                    focusAction: !cancelFirst,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    Future<void> holdUntilMenu(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
        await tester.pump();
      }
    }

    testWidgets('le dialogue s’ouvre touche enfoncée, sans rien valider', (
      tester,
    ) async {
      await pumpMenuTile(tester);
      await holdUntilMenu(tester);
      expect(find.text('Retirer ?'), findsOneWidget);
      expect(answer, isNull);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('Retirer ?'), findsOneWidget);
      expect(answer, isNull);
    });

    testWidgets('après le relâchement, un nouvel appui valide', (tester) async {
      await pumpMenuTile(tester);
      await holdUntilMenu(tester);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(answer, isTrue);
    });

    testWidgets('« Annuler » d’abord : un nouvel appui annule', (tester) async {
      await pumpMenuTile(tester, cancelFirst: true);
      await holdUntilMenu(tester);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(answer, isFalse);
    });

    testWidgets('le dialogue fermé, OK court ouvre la fiche aussitôt', (
      tester,
    ) async {
      await pumpMenuTile(tester, cancelFirst: true);
      await holdUntilMenu(tester);
      // Le relâchement va au dialogue, pas à la tuile.
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(answer, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(taps, 1);
    });
  });
}
