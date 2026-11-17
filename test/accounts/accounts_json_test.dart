import 'dart:convert';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../json_generators.dart';

Account _account(Gen gen) => Account(
  id: gen.safeId(),
  name: gen.text(),
  host: gen.text(),
  username: gen.text(),
  password: gen.text(),
  userAgent: gen.text(),
);

AccountsState _state(Gen gen) {
  var state = const AccountsState();
  for (var i = 0; i < gen.between(0, 5); i++) {
    state = state.withAccount(_account(gen), activate: gen.chance());
  }
  return state;
}

String _encode(AccountsState state) => jsonEncode(state.toJson());

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('aller-retour', () {
    test('200 états générés : relus, puis réencodés à l\'identique', () {
      final gen = Gen(80);
      for (var i = 0; i < 200; i++) {
        final state = _state(gen);
        final first = _encode(state);
        final back = AccountsState.fromJson(jsonDecode(first));
        expect(_encode(back), first, reason: 'itération $i');
        expect(back.activeId, state.activeId);
        expect(back.accounts, state.accounts);
      }
    });

    test(
      '50 états par le coffre (faux de stockage), rouvert à chaque fois',
      () async {
        final gen = Gen(81);
        for (var i = 0; i < 50; i++) {
          final state = _state(gen);
          await (await AccountStore.open()).save(state);
          final reopened = await AccountStore.open();
          expect(
            _encode(reopened.current),
            _encode(state),
            reason: 'itération $i',
          );
          expect(reopened.unreadable, isFalse);
        }
      },
    );
  });

  group('fichier abîmé', () {
    test(
      'enregistrement tronqué en 100 endroits : sans compte, illisible',
      () async {
        final gen = Gen(82);
        final text = _encode(_state(gen).withAccount(_account(gen)));
        for (var i = 0; i < 100; i++) {
          final part = text.substring(0, gen.between(1, text.length - 1));
          FlutterSecureStorage.setMockInitialValues({'accounts': part});
          final store = await AccountStore.open();
          expect(
            store.current.accounts,
            isEmpty,
            reason: 'coupé à ${part.length}',
          );
          expect(store.unreadable, isTrue);
          // La première écriture relit d'abord, puis garde le texte de côté :
          // il peut porter des identifiants, il reste dans le coffre.
          expect(await store.recover(), isNull);
          const storage = FlutterSecureStorage();
          expect(await storage.read(key: 'accounts.bak'), part);
          expect(await storage.read(key: 'accounts'), part);
        }
      },
    );

    test(
      'JSON valide mais pas un objet : sans compte, pas illisible',
      () async {
        for (final raw in [
          '[]',
          '"texte"',
          '42',
          'null',
          '{}',
          '{"accounts": 5}',
        ]) {
          FlutterSecureStorage.setMockInitialValues({'accounts': raw});
          final store = await AccountStore.open();
          expect(store.current.accounts, isEmpty, reason: raw);
          expect(store.current.activeId, isNull);
          expect(store.unreadable, isFalse);
        }
      },
    );

    test('comptes mal typés ignorés un à un, actif inconnu remplacé', () {
      final good = Account(
        id: 'a',
        name: 'n',
        host: 'h',
        username: 'u',
        password: 'p',
        userAgent: 'ua',
      );
      final state = AccountsState.fromJson({
        'active': 'inconnu',
        'accounts': [
          5,
          null,
          {'id': 'b'},
          {...good.toJson(), 'id': 'a/../b'},
          {...good.toJson(), 'id': ''},
          {...good.toJson(), 'password': null},
          // Un nombre à la place du texte : lu comme du texte.
          {...good.toJson(), 'id': 7, 'username': 12},
          good.toJson(),
        ],
      });
      expect(state.accounts.map((a) => a.id), ['7', 'a']);
      expect(state.accounts.first.username, '12');
      expect(state.activeId, '7');
    });

    test('champ inconnu en plus : ignoré, perdu à la réécriture', () async {
      final gen = Gen(83);
      final account = _account(gen);
      final json = {
        'futur': true,
        'active': account.id,
        'accounts': [
          {...account.toJson(), 'nouveau': 1},
        ],
      };
      FlutterSecureStorage.setMockInitialValues({'accounts': jsonEncode(json)});
      final store = await AccountStore.open();
      expect(store.current.accounts, [account]);
      await store.save(store.current);
      final raw = await const FlutterSecureStorage().read(key: 'accounts');
      expect(raw, isNot(contains('futur')));
      expect(raw, isNot(contains('nouveau')));
    });

    test('valeurs mutées au hasard : jamais d\'exception', () async {
      final gen = Gen(84);
      for (var i = 0; i < 200; i++) {
        final mutated = gen.mutate(jsonDecode(_encode(_state(gen))));
        final state = AccountsState.fromJson(mutated);
        // Toujours un compte actif dès qu'il y a un compte, et seulement alors.
        expect(state.active != null, state.accounts.isNotEmpty, reason: '$i');
        _encode(state);
      }
    });
  });
}
