import 'package:couchplay/catalog/poster_grid.dart';
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

  // Relevé sur l'émulateur TV avec un clavier USB maintenu : un appui, puis
  // des dizaines de répétitions, puis le relâchement. Une fois le menu ouvert,
  // ces répétitions ne doivent pas activer son premier bouton (« Retirer »).
  testWidgets('OK maintenu : le menu ouvert ne reçoit pas les répétitions', (
    tester,
  ) async {
    var removed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: SizedBox(
              width: 170,
              child: PosterTile(
                title: 'Horizon',
                imageUrl: null,
                onTap: () {},
                onMenu: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    actions: [
                      TextButton(
                        autofocus: true,
                        onPressed: () => removed++,
                        child: const Text('Retirer'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.text('Retirer'), findsOneWidget);
    expect(removed, 0);

    // Un appui suivant, court, agit normalement sur le menu.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(removed, 1);
  });
}
