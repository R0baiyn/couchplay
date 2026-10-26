import 'package:couchplay/accounts/account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hostError', () {
    test('accepte http et https, avec ou sans port ni / final', () {
      for (final host in [
        'http://serveur.com',
        'http://serveur.com:8080',
        'https://serveur.com/',
        '  HTTP://192.168.1.10:25461  ',
      ]) {
        expect(hostError(host), isNull, reason: host);
      }
    });

    test('refuse un hôte vide, sans schéma ou avec un autre schéma', () {
      for (final host in ['', '   ', 'serveur.com:8080', 'ftp://serveur.com']) {
        expect(hostError(host), isNotNull, reason: host);
      }
    });

    test('refuse un chemin, des paramètres ou des identifiants', () {
      for (final host in [
        'http://serveur.com/player_api.php',
        'http://serveur.com:8080/get.php',
        'http://serveur.com?a=1',
        'http://serveur.com#x',
        'http://moi:secret@serveur.com', // pre-push:allow : valeur de test fictive
      ]) {
        expect(hostError(host), isNotNull, reason: host);
      }
    });
  });

  test('normalizeHost retire le / final et met le schéma en minuscules', () {
    expect(
      normalizeHost(' HTTP://Serveur.com:8080/ '),
      'http://serveur.com:8080',
    );
    expect(normalizeHost('https://serveur.com'), 'https://serveur.com');
  });

  group('Account', () {
    const account = Account(
      id: 'abc',
      name: 'Salon',
      host: 'http://serveur.com',
      username: 'moi',
      password: 'motdepasse', // pre-push:allow : valeur de test fictive
      userAgent: 'Agent',
    );

    test('survit à un aller-retour JSON', () {
      expect(Account.fromJson(account.toJson()), account);
    });

    test('ignore une entrée incomplète, complète les champs facultatifs', () {
      expect(Account.fromJson({'id': 'abc', 'host': 'http://s.com'}), isNull);
      expect(
        Account.fromJson({...account.toJson(), 'id': '../autre'}),
        isNull,
        reason: 'un id qui sortirait du dossier accounts est rejeté',
      );
      final minimal = Account.fromJson({
        'id': 7,
        'host': 'http://s.com',
        'username': 'moi',
        'password': 'mdp',
      })!;
      expect(minimal.id, '7');
      expect(minimal.name, 'http://s.com');
      expect(minimal.userAgent, defaultUserAgent);
    });

    test('toString ne montre pas les identifiants', () {
      expect('$account', isNot(contains('moi')));
      expect('$account', isNot(contains('motdepasse')));
    });

    test(
      'newId donne 32 caractères hexadécimaux, différents à chaque fois',
      () {
        final ids = {for (var i = 0; i < 100; i++) Account.newId()};
        expect(ids, hasLength(100));
        expect(ids.every(RegExp(r'^[0-9a-f]{32}$').hasMatch), isTrue);
      },
    );
  });
}
