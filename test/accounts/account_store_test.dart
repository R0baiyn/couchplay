import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/accounts/server_session.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Account _account(String id, {String password = 'mdp'}) => Account(
  id: id,
  name: 'Compte $id',
  host: 'http://serveur-$id.com',
  username: 'moi',
  password: password,
  userAgent: defaultUserAgent,
);

void main() {
  group('AccountsState', () {
    test('le premier compte ajouté devient actif', () {
      final state = const AccountsState().withAccount(_account('a'));
      expect(state.activeId, 'a');
    });

    test('ajouter un second compte garde l\'actif, sauf si demandé', () {
      final one = const AccountsState().withAccount(_account('a'));
      expect(one.withAccount(_account('b')).activeId, 'a');
      expect(one.withAccount(_account('b'), activate: true).activeId, 'b');
    });

    test('modifier un compte le remplace sans changer son id ni sa place', () {
      final state = const AccountsState()
          .withAccount(_account('a'))
          .withAccount(_account('b'))
          .withAccount(_account('a', password: 'neuf'));
      expect(state.accounts.map((a) => a.id), ['a', 'b']);
      expect(state.accounts.first.password, 'neuf');
    });

    test('supprimer l\'actif active le premier restant', () {
      final state = const AccountsState()
          .withAccount(_account('a'))
          .withAccount(_account('b'), activate: true)
          .without('b');
      expect(state.activeId, 'a');
      expect(state.without('a').activeId, isNull);
      expect(state.without('a').accounts, isEmpty);
    });

    test('un compte actif inconnu est remplacé par le premier', () {
      final state = AccountsState.fromJson({
        'active': 'disparu',
        'accounts': [_account('a').toJson(), _account('b').toJson()],
      });
      expect(state.activeId, 'a');
      expect(state.withActive('inconnu').activeId, 'a');
    });

    test('les entrées illisibles sont ignorées', () {
      final state = AccountsState.fromJson({
        'active': 'a',
        'accounts': [
          {'id': 'x'},
          'texte',
          _account('a').toJson(),
        ],
      });
      expect(state.accounts.map((a) => a.id), ['a']);
    });
  });

  group('AccountStore', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('sans données : aucun compte', () async {
      expect((await AccountStore.open()).current.accounts, isEmpty);
    });

    test('les comptes et l\'actif survivent à une réouverture', () async {
      final state = const AccountsState()
          .withAccount(_account('a'))
          .withAccount(_account('b'), activate: true);
      await (await AccountStore.open()).save(state);

      final reopened = (await AccountStore.open()).current;
      expect(reopened.accounts, state.accounts);
      expect(reopened.activeId, 'b');
    });

    test('un contenu corrompu donne une liste vide, sans planter', () async {
      FlutterSecureStorage.setMockInitialValues({'accounts': '{pas du json'});
      expect((await AccountStore.open()).current.accounts, isEmpty);
    });
  });

  group('AccountsNotifier', () {
    late Directory root;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      root = Directory.systemTemp.createTempSync('couchplay_store_');
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<ProviderContainer> containerWith(List<Account> accounts) async {
      var state = const AccountsState();
      for (final account in accounts) {
        state = state.withAccount(account);
      }
      final store = await AccountStore.open();
      await store.save(state);
      return ProviderContainer.test(
        overrides: [
          accountStoreProvider.overrideWithValue(store),
          accountFilesProvider.overrideWithValue(
            AccountFiles(Directory('${root.path}/accounts')),
          ),
          serverClientFactoryProvider.overrideWithValue(
            (a) => ServerClient(
              host: a.host,
              username: a.username,
              password: a.password,
              userAgent: a.userAgent,
            ),
          ),
        ],
      );
    }

    test(
      'un clic pendant une suppression ne fait pas revenir le compte',
      () async {
        final container = await containerWith([_account('a'), _account('b')]);
        final notifier = container.read(accountsProvider.notifier);

        // Sans écritures en série, activate partirait de l'état d'avant la
        // suppression et réécrirait « a ».
        await Future.wait([notifier.remove('a'), notifier.activate('a')]);

        expect(container.read(accountsProvider).accounts.map((x) => x.id), [
          'b',
        ]);
        final reopened = (await AccountStore.open()).current;
        expect(reopened.accounts.map((x) => x.id), ['b']);
      },
    );

    test('renommer le compte actif garde le même client serveur', () async {
      final container = await containerWith([_account('a')]);
      container.listen(serverClientProvider, (_, _) {});
      final before = container.read(serverClientProvider);

      await container
          .read(accountsProvider.notifier)
          .save(
            Account.fromJson({..._account('a').toJson(), 'name': 'Salon'})!,
          );
      expect(container.read(serverClientProvider), same(before));

      await container
          .read(accountsProvider.notifier)
          .save(_account('a', password: 'neuf'));
      expect(container.read(serverClientProvider), isNot(same(before)));
    });
  });

  test('removeOrphans efface les dossiers des comptes disparus', () async {
    final root = Directory.systemTemp.createTempSync('couchplay_orphans_');
    addTearDown(() => root.deleteSync(recursive: true));
    final files = AccountFiles(Directory('${root.path}/accounts'));
    for (final id in ['garde', 'orphelin']) {
      files.of(id).createSync(recursive: true);
    }

    await files.removeOrphans({'garde'});

    expect(files.of('garde').existsSync(), isTrue);
    expect(files.of('orphelin').existsSync(), isFalse);
  });
}
