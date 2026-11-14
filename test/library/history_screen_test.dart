import 'package:couchplay/library/history_screen.dart';
import 'package:couchplay/library/library.dart';
import 'package:couchplay/library/library_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/library_container.dart';

void main() {
  testWidgets(
    'télécommande : → depuis une ligne atteint sa ✕, Entrée la retire',
    (tester) async {
      final container = await libraryContainer(tester);
      final library = container.read(libraryProvider.notifier);
      for (final name in ['Ancien', 'Récent']) {
        await tester.runAsync(
          () => library.saveProgress(
            PlayItem.movie(id: name, extension: 'mkv', name: name),
            position: const Duration(minutes: 10),
            duration: const Duration(minutes: 90),
          ),
        );
        // Attend que l'horloge ait avancé : l'ordre repose sur `updatedAt`.
        final saved = DateTime.now();
        await tester.runAsync(() async {
          while (!DateTime.now().isAfter(saved)) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        });
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HistoryScreen()),
        ),
      );
      // La ligne la plus récente est la première.
      Focus.of(tester.element(find.text('Récent'))).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(find.text('Récent'), findsNothing);
      expect(find.text('Ancien'), findsOneWidget);
    },
  );

  testWidgets("un favori ajouté ne refait pas l'historique", (tester) async {
    final container = await libraryContainer(tester);
    final library = container.read(libraryProvider.notifier);
    await tester.runAsync(
      () => library.saveProgress(
        const PlayItem.movie(id: '1', extension: 'mkv', name: 'Horizon'),
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 90),
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    var builds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is HistoryScreen) builds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    for (final key in ['movie:2', 'movie:3', 'movie:4']) {
      await tester.runAsync(() => library.addFavorite(key: key, name: key));
      await tester.pump();
    }

    expect(builds, 0);
    expect(find.text('Horizon'), findsOneWidget);
  });
}
