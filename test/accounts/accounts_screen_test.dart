import 'dart:async';
import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/accounts/accounts_screen.dart';
import 'package:couchplay/accounts/server_session.dart';
import 'package:couchplay/app.dart';
import 'package:couchplay/search/search_index.dart';

import 'package:couchplay/server/server_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';
import '../support/settle.dart';

Account _account(String id) => Account(
  id: id,
  name: 'Compte $id',
  host: 'http://serveur-$id.com',
  username: 'moi',
  password: 'mdp',
  userAgent: defaultUserAgent,
);

/// Index qui ne finit jamais de charger : aucune requête en vol.
class _PendingIndex extends SearchIndexNotifier {
  @override
  Future<SearchIndex> build() => Completer<SearchIndex>().future;
}

void main() {
  late Directory root;
  late AccountFiles files;

  setUp(() {
    root = Directory.systemTemp.createTempSync('couchplay_accounts_');
    files = AccountFiles(Directory('${root.path}/accounts'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<ProviderContainer> pumpAccounts(
    WidgetTester tester,
    List<Account> accounts,
  ) async {
    var state = const AccountsState();
    for (final account in accounts) {
      state = state.withAccount(account);
    }
    FlutterSecureStorage.setMockInitialValues({});
    final store = await tester.runAsync(() async {
      await (await AccountStore.open()).save(state);
      return AccountStore.open();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountStoreProvider.overrideWithValue(store!),
          accountFilesProvider.overrideWithValue(files),
          // Sans objet ici : l'index de recherche, chargé en arrière-plan
          // derrière l'accueil, laisserait des requêtes en vol.
          searchIndexProvider.overrideWith(_PendingIndex.new),
          serverClientFactoryProvider.overrideWithValue(
            (account) => ServerClient(
              host: account.host,
              username: account.username,
              password: account.password,
              userAgent: account.userAgent,
              adapter: FakeAdapter.replying(activeAccountJson),
            ),
          ),
        ],
        child: MaterialApp(
          home: const HomeGate(),
          routes: {'/comptes': (_) => const AccountsScreen()},
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeGate)),
    );
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/comptes');
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('toucher un compte en fait le compte actif', (tester) async {
    final container = await pumpAccounts(tester, [
      _account('a'),
      _account('b'),
    ]);
    expect(container.read(activeAccountProvider)!.id, 'a');

    await tester.tap(find.text('Compte b'));
    await settle(tester);

    expect(container.read(activeAccountProvider)!.id, 'b');
    final reopened = await tester.runAsync(AccountStore.open);
    expect(reopened!.current.activeId, 'b');
  });

  testWidgets('supprimer l\'actif efface son dossier et active l\'autre', (
    tester,
  ) async {
    final container = await pumpAccounts(tester, [
      _account('a'),
      _account('b'),
    ]);
    final data = files.of('a');
    await tester.runAsync(() async {
      await data.create(recursive: true);
      await File('${data.path}/library.json').writeAsString('{}');
    });

    await tester.tap(find.byTooltip('Supprimer').first);
    await tester.pumpAndSettle();
    expect(find.text('Supprimer « Compte a » ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await settle(tester);

    expect(container.read(accountsProvider).accounts.map((a) => a.id), ['b']);
    expect(container.read(activeAccountProvider)!.id, 'b');
    expect(await tester.runAsync(data.exists), isFalse);
  });

  testWidgets('annuler la suppression ne change rien', (tester) async {
    final container = await pumpAccounts(tester, [_account('a')]);

    await tester.tap(find.byTooltip('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await settle(tester);

    expect(container.read(accountsProvider).accounts, hasLength(1));
  });

  testWidgets('supprimer le dernier compte ramène à la connexion', (
    tester,
  ) async {
    await pumpAccounts(tester, [_account('a')]);

    await tester.tap(find.byTooltip('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await settle(tester);

    expect(find.text('Ajouter un compte'), findsOneWidget);
    expect(find.byType(AccountsScreen), findsNothing);
  });

  testWidgets('modifier un compte garde son id et l\'actif', (tester) async {
    final container = await pumpAccounts(tester, [
      _account('a'),
      _account('b'),
    ]);

    await tester.tap(find.byTooltip('Modifier').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(3), 'nouveau');
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);

    final b = container
        .read(accountsProvider)
        .accounts
        .firstWhere((a) => a.id == 'b');
    expect(b.password, 'nouveau');
    expect(container.read(activeAccountProvider)!.id, 'a');
    expect(find.byType(AccountsScreen), findsOneWidget);
  });

  testWidgets('modifier sans retaper le mot de passe le conserve', (
    tester,
  ) async {
    final container = await pumpAccounts(tester, [_account('a')]);

    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(3))
          .controller!
          .text,
      isEmpty,
      reason: 'le mot de passe enregistré n\'est jamais affiché',
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'Chambre');
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);

    final a = container.read(accountsProvider).accounts.single;
    expect(a.name, 'Chambre');
    expect(a.password, 'mdp');
  });

  test('un id de compte ne peut pas sortir du dossier accounts', () {
    for (final id in ['..', '../x', r'a\b', 'a/b', '']) {
      expect(() => files.of(id), throwsArgumentError, reason: id);
    }
  });
}
