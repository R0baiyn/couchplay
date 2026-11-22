import 'dart:convert';
import 'dart:io';

import 'package:couchplay/downloads/download.dart';
import 'package:couchplay/library/library.dart';
import 'package:flutter_test/flutter_test.dart';

import '../json_generators.dart';

Download _download(Gen gen, {bool running = false}) {
  final status = gen.pick(
    DownloadStatus.values
        .where((s) => running || s != DownloadStatus.running)
        .toList(),
  );
  final size = gen.chance(0.2) ? 0 : gen.between(1, 4000000000);
  return Download(
    item: gen.item(),
    size: size,
    received: size == 0 ? 0 : gen.between(0, size),
    status: status,
    error: status == DownloadStatus.failed && gen.chance(0.8)
        ? gen.text()
        : null,
    addedAt: gen.date(),
    deletePending: status == DownloadStatus.ready && gen.chance(0.2),
  );
}

String _encode(Map<String, Download> entries) => jsonEncode({
  for (final MapEntry(:key, :value) in entries.entries) key: value.toJson(),
});

void main() {
  late Directory dir;
  late File manifest;
  late DownloadsStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('couchplay_downloads_json_');
    manifest = File('${dir.path}${Platform.pathSeparator}downloads.json');
    store = DownloadsStore(manifest, Directory('${dir.path}/videos'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Map<String, Download> generated(Gen gen) {
    final entries = <String, Download>{};
    for (var i = 0; i < gen.between(0, 6); i++) {
      final download = _download(gen);
      entries[download.key] = download;
      if (download.status == DownloadStatus.ready) {
        // Une vidéo prête a son fichier : sinon la lecture la retire.
        store.fileOf(download)
          ..createSync(recursive: true)
          ..writeAsStringSync('x');
      }
    }
    return entries;
  }

  group('aller-retour', () {
    test('200 manifestes générés : relus, puis réencodés à l\'identique', () {
      final gen = Gen(50);
      for (var i = 0; i < 200; i++) {
        final entries = <String, Download>{};
        for (var j = 0; j < gen.between(0, 6); j++) {
          final download = _download(gen);
          entries[download.key] = download;
        }
        for (final MapEntry(:key, :value) in entries.entries) {
          final back = Download.fromJson(
            key,
            jsonDecode(jsonEncode(value.toJson())),
          );
          expect(back, isNotNull, reason: '$key itération $i');
          expect(jsonEncode(back!.toJson()), jsonEncode(value.toJson()));
        }
      }
    });

    test('50 manifestes par l\'écriture atomique réelle', () async {
      final gen = Gen(51);
      for (var i = 0; i < 50; i++) {
        final entries = generated(gen);
        await store.save(entries);
        final loaded = DownloadsStore(manifest, store.videos).load();
        expect(_encode(loaded), _encode(entries), reason: 'itération $i');
        expect(loaded.keys, entries.keys, reason: 'ordre d\'ajout gardé');
      }
      expect(File('${manifest.path}.bak').existsSync(), isFalse);
    });

    test('en cours : relu en attente, le reste intact', () {
      final gen = Gen(52);
      for (var i = 0; i < 50; i++) {
        final running = _download(
          gen,
          running: true,
        ).copyWith(status: DownloadStatus.running);
        final back = Download.fromJson(
          running.key,
          jsonDecode(jsonEncode(running.toJson())),
        )!;
        expect(back.status, DownloadStatus.queued);
        expect(back.size, running.size);
        expect(back.received, running.received);
      }
    });
  });

  group('fichier abîmé', () {
    File bak() => File('${manifest.path}.bak');

    test('vide : mis de côté en .bak, liste vide, on peut réécrire', () {
      manifest.writeAsStringSync('');
      expect(store.load(), isEmpty);
      expect(manifest.existsSync(), isFalse);
      expect(bak().readAsStringSync(), '');
      expect(store.unreadable, isFalse);
    });

    test('tronqué en 100 endroits : liste vide, original gardé en .bak', () {
      final gen = Gen(53);
      final text = const JsonEncoder.withIndent(' ').convert({
        'version': 1,
        'downloads': {
          for (final d in [_download(gen), _download(gen)]) d.key: d.toJson(),
        },
      });
      for (var i = 0; i < 100; i++) {
        final part = text.substring(0, gen.between(1, text.length - 3));
        manifest.writeAsStringSync(part);
        if (bak().existsSync()) bak().deleteSync();
        final reader = DownloadsStore(manifest, store.videos);
        expect(reader.load(), isEmpty, reason: 'coupé à ${part.length}');
        expect(manifest.existsSync(), isFalse);
        expect(bak().readAsStringSync(), part);
        expect(reader.unreadable, isFalse);
      }
    });

    // D-063 : laissé tel quel, il donnait une liste vide et le rangement
    // effaçait toutes les vidéos.
    test('JSON valide mais pas un manifeste : liste vide, mis de côté', () {
      for (final content in [
        '[]',
        '"texte"',
        '42',
        'null',
        '{"downloads": 5}',
      ]) {
        manifest.writeAsStringSync(content);
        if (bak().existsSync()) bak().deleteSync();
        final reader = DownloadsStore(manifest, store.videos);
        expect(reader.load(), isEmpty, reason: content);
        expect(manifest.existsSync(), isFalse, reason: content);
        expect(bak().readAsStringSync(), content);
        expect(reader.unreadable, isFalse);
      }
    });

    test('entrées mal typées ignorées une à une', () {
      store.fileOf(
          Download(
            item: const PlayItem.movie(id: '5', extension: 'mkv', name: 'x'),
            addedAt: DateTime.utc(2026),
          ),
        )
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      Map<String, Object?> entry(Object? status, {Object? size = 10}) => {
        'name': 'Film',
        'extension': 'mkv',
        'size': size,
        'status': status,
      };
      manifest.writeAsStringSync(
        jsonEncode({
          'downloads': {
            'movie:1': 5,
            'movie:2': entry('inconnu'),
            'movie:3': entry(null),
            'movie:4': entry('queued', size: 'dix'),
            // Prête, mais sans fichier sur le disque : retirée.
            'movie:6': entry('ready'),
            'movie:5': entry('ready', size: '1e3'),
            // Id ou extension qui sortiraient du dossier : refusés.
            'movie:../x': entry('queued'),
            'movie:7': {...entry('queued'), 'extension': 'm/kv'},
            // Entrée d'un format inconnu : sans clé connue.
            'foo:8': entry('queued'),
          },
        }),
      );
      final entries = store.load();
      expect(entries.keys, ['movie:4', 'movie:5']);
      // Taille mal typée : 0 ; texte numérique : lu.
      expect(entries['movie:4']!.size, 0);
      expect(entries['movie:5']!.size, 1000);
      expect(entries['movie:5']!.status, DownloadStatus.ready);
    });

    test('champ inconnu en plus : ignoré, perdu à la réécriture', () async {
      manifest.writeAsStringSync(
        jsonEncode({
          'futur': 1,
          'downloads': {
            'movie:1': {
              'name': 'A',
              'extension': 'mkv',
              'status': 'paused',
              'nouveau': [1],
            },
          },
        }),
      );
      final entries = store.load();
      expect(entries['movie:1']!.status, DownloadStatus.paused);
      await store.save(entries);
      expect(manifest.readAsStringSync(), isNot(contains('nouveau')));
      expect(manifest.readAsStringSync(), isNot(contains('futur')));
    });

    test('valeurs mutées au hasard : jamais d\'exception', () {
      final gen = Gen(54);
      for (var i = 0; i < 100; i++) {
        final entries = generated(gen);
        final json = {
          'version': 1,
          'downloads': {
            for (final MapEntry(:key, :value) in entries.entries)
              key: value.toJson(),
          },
        };
        final mutated = gen.mutate(json);
        final String text;
        try {
          text = jsonEncode(mutated);
        } on JsonUnsupportedObjectError {
          continue;
        }
        manifest.writeAsStringSync(text);
        final reader = DownloadsStore(manifest, store.videos);
        expect(reader.load, returnsNormally, reason: text);
      }
    });
  });
}
