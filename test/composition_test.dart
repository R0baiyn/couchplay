import 'dart:io';

import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/catalog/catalog_settings_screen.dart';
import 'package:couchplay/live/live_settings_view.dart';
import 'package:couchplay/logging.dart';
import 'package:couchplay/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/settle.dart';

void main() {
  testWidgets('l\'app lancée a la section « Chaînes » dans les réglages du '
      'catalogue', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('couchplay_composition_');
    addTearDown(() => root.deleteSync(recursive: true));
    final accounts = await tester.runAsync(AccountStore.open);

    // Sans compte : l'écran de connexion, aucune requête.
    final container = startApp(
      accounts: accounts!,
      support: root,
      downloads: Directory('${root.path}/downloads'),
      version: '0.0.0',
      television: false,
    );
    await settle(tester);

    expect(
      container.read(catalogSettingsSectionsProvider),
      contains(isA<LiveCategorySettings>()),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    // Le journal est dans `root` : fermé avant l'effacement (Windows).
    await tester.runAsync(() async {
      await SerialFileWriter.flushAll();
      await closeJournal();
    });
  });
}
