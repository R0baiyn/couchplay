import 'dart:convert';
import 'dart:io';

import 'package:couchplay/accounts/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../json_generators.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('couchplay_settings_json_');
    file = File('${dir.path}${Platform.pathSeparator}settings.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  AppSettings read() {
    final c = ProviderContainer(
      overrides: [appSettingsFileProvider.overrideWithValue(file)],
    );
    addTearDown(c.dispose);
    return c.read(appSettingsProvider);
  }

  String encode(AppSettings s) => jsonEncode(s.toJson());

  group('aller-retour', () {
    test(
      'toutes les combinaisons : relues, puis réencodées à l\'identique',
      () {
        for (var bits = 0; bits < 8; bits++) {
          final settings = AppSettings(
            debug: bits & 1 != 0,
            wifiOnly: bits & 2 != 0,
            deleteWatched: bits & 4 != 0,
          );
          final first = encode(settings);
          expect(encode(AppSettings.fromJson(jsonDecode(first))), first);
        }
      },
    );

    test(
      '200 suites de réglages écrites par le notifier, relues du fichier',
      () async {
        final gen = Gen(60);
        final c = ProviderContainer(
          overrides: [appSettingsFileProvider.overrideWithValue(file)],
        );
        addTearDown(c.dispose);
        final notifier = c.read(appSettingsProvider.notifier);
        for (var i = 0; i < 200; i++) {
          final value = gen.chance();
          await switch (gen.between(0, 2)) {
            0 => notifier.setDebug(value),
            1 => notifier.setWifiOnly(value),
            _ => notifier.setDeleteWatched(value),
          };
          expect(encode(read()), encode(c.read(appSettingsProvider)));
        }
      },
    );
  });

  group('fichier abîmé', () {
    void expectDefaults(AppSettings s) =>
        expect(encode(s), encode(const AppSettings()));

    test('vide, blanc, tronqué, pas du JSON : réglages par défaut', () {
      final text = encode(const AppSettings(debug: true, wifiOnly: false));
      final gen = Gen(61);
      final bad = [
        '',
        '   ',
        '{pas du json',
        for (var i = 0; i < 50; i++)
          text.substring(0, gen.between(1, text.length - 1)),
      ];
      for (final content in bad) {
        file.writeAsStringSync(content);
        expectDefaults(read());
        // Rien n'est mis de côté ni réécrit à la lecture.
        expect(file.readAsStringSync(), content);
        expect(File('${file.path}.bak').existsSync(), isFalse);
      }
    });

    test('JSON valide mais pas un objet : réglages par défaut', () {
      for (final content in ['[]', '"texte"', '42', 'null', 'true']) {
        file.writeAsStringSync(content);
        expectDefaults(read());
      }
    });

    test(
      'valeurs mal typées : lues quand c\'est sans ambiguïté, sinon défaut',
      () {
        file.writeAsStringSync(
          jsonEncode({
            'debug': 'yes',
            'wifiOnly': 0,
            'deleteWatched': 'peut-être',
          }),
        );
        final s = read();
        expect((s.debug, s.wifiOnly, s.deleteWatched), (true, false, false));
        file.writeAsStringSync(
          jsonEncode({'debug': [], 'wifiOnly': {}, 'deleteWatched': null}),
        );
        expectDefaults(read());
      },
    );

    test('champ inconnu en plus : ignoré, perdu à la réécriture', () async {
      file.writeAsStringSync(jsonEncode({'debug': true, 'futur': 3}));
      final c = ProviderContainer(
        overrides: [appSettingsFileProvider.overrideWithValue(file)],
      );
      addTearDown(c.dispose);
      expect(c.read(appSettingsProvider).debug, isTrue);
      await c.read(appSettingsProvider.notifier).setWifiOnly(false);
      expect(file.readAsStringSync(), isNot(contains('futur')));
    });

    test('valeurs mutées au hasard : jamais d\'exception', () {
      final gen = Gen(62);
      for (var i = 0; i < 300; i++) {
        final mutated = gen.mutate(
          jsonDecode(encode(const AppSettings(debug: true))),
          rate: 0.3,
        );
        encode(AppSettings.fromJson(mutated));
      }
    });
  });
}
