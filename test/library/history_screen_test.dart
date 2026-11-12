import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/library/history_screen.dart';
import 'package:couchplay/library/library.dart';
import 'package:couchplay/library/library_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'télécommande : → depuis une ligne atteint sa ✕, Entrée la retire',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('couchplay_history_');
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } on FileSystemException {
          // Écriture encore en cours sous Windows : le dossier reste, sans effet.
        }
      });
      FlutterSecureStorage.setMockInitialValues({});
      final (store, files) = (await tester.runAsync(() async {
        final store = await AccountStore.open();
        await store.save(
          const AccountsState().withAccount(
            const Account(
              id: 'a',
              name: 'a',
              host: 'http://example.com',
              username: 'u',
              password: 'p',
              userAgent: defaultUserAgent,
            ),
          ),
        );
        final files = AccountFiles(Directory('${root.path}/accounts'));
        await files.sync({'a'});
        return (store, files);
      }))!;
      final container = ProviderContainer.test(
        overrides: [
          accountStoreProvider.overrideWithValue(store),
          accountFilesProvider.overrideWithValue(files),
        ],
      );
      final library = container.read(libraryProvider.notifier);
      for (final name in ['Ancien', 'Récent']) {
        await tester.runAsync(
          () => library.saveProgress(
            PlayItem.movie(id: name, extension: 'mkv', name: name),
            position: const Duration(minutes: 10),
            duration: const Duration(minutes: 90),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
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
}
