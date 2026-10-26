import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_store.dart';
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
      expect((await AccountStore.open()).initial.accounts, isEmpty);
    });

    test('les comptes et l\'actif survivent à une réouverture', () async {
      final state = const AccountsState()
          .withAccount(_account('a'))
          .withAccount(_account('b'), activate: true);
      await (await AccountStore.open()).save(state);

      final reopened = (await AccountStore.open()).initial;
      expect(reopened.accounts, state.accounts);
      expect(reopened.activeId, 'b');
    });

    test('un contenu corrompu donne une liste vide, sans planter', () async {
      FlutterSecureStorage.setMockInitialValues({'accounts': '{pas du json'});
      expect((await AccountStore.open()).initial.accounts, isEmpty);
    });
  });
}
