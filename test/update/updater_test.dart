import 'dart:io';

import 'package:couchplay/update/updater.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

void main() {
  group('isNewer', () {
    test('compare chaque numéro, pas le texte', () {
      expect(isNewer('0.1.10', '0.1.9'), isTrue);
      expect(isNewer('0.1.9', '0.1.10'), isFalse);
      expect(isNewer('1.0.0', '0.9.9'), isTrue);
    });

    test('ignore le préfixe v et le suffixe +build', () {
      expect(isNewer('v0.1.1', '0.1.0+1'), isTrue);
      expect(isNewer('v0.1.0', '0.1.0+7'), isFalse);
    });

    test('une version illisible n\'est jamais plus récente', () {
      expect(isNewer('latest', '0.1.0'), isFalse);
      expect(isNewer('v0.2', '0.1.0'), isFalse);
    });
  });

  group('updateFrom', () {
    Map<String, Object?> release({String tag = 'v0.1.1'}) => {
      'tag_name': tag,
      'body': '- Nouvelle icône\n',
      'assets': [
        {
          'name': 'couchplay-0.1.1-windows-portable.zip',
          'browser_download_url': 'https://github.com/R0baiyn/couchplay/releases/download/v0.1.1/couchplay-0.1.1-windows-portable.zip',
          'size': 30,
        },
        {
          'name': 'couchplay-0.1.1-windows-setup.exe',
          'browser_download_url': 'https://github.com/R0baiyn/couchplay/releases/download/v0.1.1/couchplay-0.1.1-windows-setup.exe',
          'size': 20,
        },
      ],
    };

    test('installée : l\'installateur', () {
      final update = updateFrom(release(), current: '0.1.0', portable: false)!;
      expect(update.version, '0.1.1');
      expect(update.notes, '- Nouvelle icône');
      expect(update.asset.path, endsWith('-windows-setup.exe'));
      expect(update.size, 20);
    });

    test('portable : le zip', () {
      final update = updateFrom(release(), current: '0.1.0', portable: true)!;
      expect(update.asset.path, endsWith('-windows-portable.zip'));
      expect(update.portable, isTrue);
    });

    test('rien si la version n\'est pas plus récente', () {
      expect(updateFrom(release(), current: '0.1.1', portable: false), isNull);
    });

    test('rien si le fichier vient d\'un autre hôte', () {
      final json = release();
      for (final asset in json['assets'] as List) {
        (asset as Map)['browser_download_url'] = 'https://example.com/x.exe';
      }
      expect(updateFrom(json, current: '0.1.0', portable: false), isNull);
    });

    test('réponse inattendue : rien, sans exception', () {
      expect(updateFrom(null, current: '0.1.0', portable: false), isNull);
      expect(
        updateFrom({'tag_name': 'v9.0.0'}, current: '0.1.0', portable: false),
        isNull,
      );
    });
  });

  group('prepare', () {
    late Directory work;
    setUp(() => work = Directory.systemTemp.createTempSync('couchplay-test'));
    tearDown(() => work.deleteSync(recursive: true));

    final update = Update(
      version: '0.1.1',
      notes: '',
      asset: Uri.parse('https://github.com/R0baiyn/couchplay/x.zip'),
      size: 3,
      portable: true,
    );

    Updater updater(FakeAdapter adapter) => Updater(
      version: '0.1.0',
      portable: true,
      appDir: work,
      workDir: Directory('${work.path}\\update'),
      adapter: adapter,
    );

    test('une redirection vers un autre hôte est refusée', () async {
      final adapter = FakeAdapter(
        (_) async => ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['https://example.com/x.zip'],
          },
        ),
      );
      await expectLater(
        updater(adapter).prepare(update),
        throwsA(isA<HttpException>()),
      );
      expect(adapter.calls, 1);
    });

    test('un échec se retente au prochain appel', () async {
      final adapter = FakeAdapter.replying('', status: 404);
      final subject = updater(adapter);
      for (var i = 0; i < 2; i++) {
        await expectLater(subject.prepare(update), throwsA(anything));
      }
      expect(adapter.calls, 2);
    });
  });

  test('téléchargement : HTTPS chez GitHub seulement', () {
    expect(
      isAllowedDownload(Uri.parse('https://github.com/R0baiyn/couchplay')),
      isTrue,
    );
    expect(
      isAllowedDownload(
        Uri.parse('https://release-assets.githubusercontent.com/x'),
      ),
      isTrue,
    );
    expect(isAllowedDownload(Uri.parse('http://github.com/x')), isFalse);
    expect(
      isAllowedDownload(Uri.parse('https://github.com.evil.io/x')),
      isFalse,
    );
  });
}
