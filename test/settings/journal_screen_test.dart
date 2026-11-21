import 'dart:io';

import 'package:couchplay/desktop_files.dart';
import 'package:couchplay/settings/journal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final folder = Directory('dossier-du-journal');

  Future<List<String>> pumpJournal(
    WidgetTester tester, {
    List<String> lines = const ['ligne 1', 'ligne 2'],
    bool desktop = true,
  }) async {
    final opened = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          journalLinesProvider.overrideWith((ref) async => lines),
          journalFolderProvider.overrideWithValue(folder),
          desktopFilesProvider.overrideWithValue(desktop),
          openFolderProvider.overrideWithValue((d) async => opened.add(d.path)),
        ],
        child: const MaterialApp(home: JournalScreen()),
      ),
    );
    await tester.pump();
    return opened;
  }

  Finder byKey(String key) => find.byKey(ValueKey(key));

  testWidgets('les lignes sont affichées, la dernière en bas', (tester) async {
    await pumpJournal(tester);
    expect(find.text('ligne 1'), findsOneWidget);
    expect(find.text('ligne 2'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('ligne 2')).dy,
      greaterThan(tester.getTopLeft(find.text('ligne 1')).dy),
    );
  });

  testWidgets('journal vide : un message, rien à copier', (tester) async {
    await pumpJournal(tester, lines: const []);
    expect(find.text('Journal vide.'), findsOneWidget);
    final copy = tester.widget<ButtonStyleButton>(
      byKey('settings.journalCopy'),
    );
    expect(copy.onPressed, isNull);
  });

  testWidgets('« Copier » met tout le texte dans le presse-papiers', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpJournal(tester);
    await tester.tap(byKey('settings.journalCopy'));
    await tester.pump();
    expect(copied, 'ligne 1\nligne 2');
    expect(find.text('Journal copié.'), findsOneWidget);
  });

  testWidgets('PC : « Ouvrir le dossier » ouvre le dossier du journal', (
    tester,
  ) async {
    final opened = await pumpJournal(tester);
    await tester.tap(byKey('settings.journalFolder'));
    await tester.pump();
    expect(opened, [folder.path]);
  });

  testWidgets('Android et TV : pas de « Ouvrir le dossier »', (tester) async {
    await pumpJournal(tester, desktop: false);
    expect(byKey('settings.journalFolder'), findsNothing);
    expect(byKey('settings.journalCopy'), findsOneWidget);
  });

  testWidgets('flèches haut et bas : le texte défile (télécommande)', (
    tester,
  ) async {
    await pumpJournal(
      tester,
      lines: [for (var i = 0; i < 300; i++) 'ligne $i'],
    );
    double offset() =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    expect(offset(), 0);
    expect(find.text('ligne 299'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(offset(), greaterThan(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(offset(), 0);

    // Déjà en bas : la touche n'est pas prise, le texte ne bouge pas.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(offset(), 0);
  });
}
