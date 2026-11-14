import 'package:couchplay/library/home_screen.dart';
import 'package:couchplay/library/library.dart';
import 'package:couchplay/library/library_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/library_container.dart';

void main() {
  testWidgets("sous le lecteur, la progression ne refait pas l'accueil ; "
      'il se met à jour au retour', (tester) async {
    final container = await libraryContainer(tester);
    final library = container.read(libraryProvider.notifier);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(navigatorKey: navigator, home: const HomeScreen()),
      ),
    );
    // Le lecteur, par-dessus l'accueil.
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pumpAndSettle();

    var builds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is HomeScreen) builds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    for (final minutes in [1, 2, 3]) {
      await tester.runAsync(
        () => library.saveProgress(
          const PlayItem.movie(id: '1', extension: 'mkv', name: 'Horizon'),
          position: Duration(minutes: minutes),
          duration: const Duration(minutes: 90),
        ),
      );
      await tester.pump();
    }
    expect(builds, 0);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Continuer à regarder'), findsOneWidget);
    expect(find.text('Horizon'), findsOneWidget);
  });
}
