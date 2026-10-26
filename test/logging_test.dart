import 'package:couchplay/logging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Valeurs fictives, assemblées par interpolation dans les URL.
  const host = 'http://srv.example.net:8080';
  const user = 'jean.d';
  const pass = 'p4ss-w0rd';

  group('redact', () {
    test(
      'masque user et mot de passe dans la query string, dans les deux ordres',
      () {
        expect(
          redact('$host/player_api.php?username=$user&password=$pass&action=x'),
          '$host/player_api.php?username=***&password=***&action=x',
        );
        expect(
          redact('$host/player_api.php?action=x&password=$pass&username=$user'),
          '$host/player_api.php?action=x&password=***&username=***',
        );
      },
    );

    test('masque des valeurs encodées en URL', () {
      final encoded = Uri.encodeQueryComponent('a&b #"c');
      expect(
        redact('$host/player_api.php?username=$user&password=$encoded'),
        '$host/player_api.php?username=***&password=***',
      );
    });

    test('masque les chemins de flux movie, series, live et timeshift', () {
      for (final kind in ['movie', 'series', 'live', 'timeshift']) {
        expect(
          redact('$host/$kind/$user/$pass/42.mkv'),
          '$host/$kind/***/***/42.mkv',
          reason: kind,
        );
      }
      expect(
        redact('$host/timeshift/$user/$pass/60/2026-10-26:20-00/42.ts'),
        '$host/timeshift/***/***/60/2026-10-26:20-00/42.ts',
      );
    });

    test('masque la forme courte hôte/user/mot de passe/id du direct', () {
      expect(redact('$host/$user/$pass/42'), '$host/***/***/42');
      expect(redact('$host/$user/$pass/42.ts'), '$host/***/***/42.ts');
    });

    test('masque les identifiants placés avant l\'hôte', () {
      expect(
        redact('http://$user:$pass@srv.example.net/x'),
        'http://***:***@srv.example.net/x',
      );
    });

    test('masque une URL au milieu d\'un message d\'erreur', () {
      final message = redact(
        'DioException [connection timeout]: '
        '$host/player_api.php?username=$user&password=$pass failed',
      );
      expect(message, isNot(contains(user)));
      expect(message, isNot(contains(pass)));
      expect(message, startsWith('DioException [connection timeout]: '));
      expect(message, endsWith(' failed'));
    });

    test('masque en plus les secrets connus, même hors d\'une URL', () {
      final message = redact(
        'mot de passe refusé : $pass (${Uri.encodeComponent(pass)})',
        secrets: [user, pass],
      );
      expect(message, 'mot de passe refusé : *** (***)');
    });

    test(
      'ignore les secrets vides et laisse un texte sans identifiant intact',
      () {
        const text =
            'Catalogue chargé : 1234 films, https://image.example.org/a.jpg';
        expect(redact(text, secrets: ['', ' ']), text);
      },
    );
  });
}
