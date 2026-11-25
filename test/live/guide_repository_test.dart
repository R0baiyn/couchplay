import 'dart:async';
import 'dart:io';

import 'package:couchplay/catalog/catalog_cache.dart';
import 'package:couchplay/live/guide.dart';
import 'package:couchplay/live/guide_repository.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

/// Date XMLTV de [t], à l'heure de Paris en hiver.
String _date(DateTime t) {
  final p = t.toUtc().add(const Duration(hours: 1));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${p.year}${two(p.month)}${two(p.day)}${two(p.hour)}${two(p.minute)}'
      '${two(p.second)} +0100';
}

/// Guide de [channels] chaînes `c<i>.fr`, [perChannel] programmes chacune
/// de 2 h 20, de maintenant − 25 h à environ + 2,3 jours (comme le vrai,
/// `Docs/DIRECT.md`), avec un résumé de [descLength] caractères.
String _guide(
  DateTime now, {
  int channels = 3,
  int perChannel = 34,
  int descLength = 40,
}) {
  final out = StringBuffer(
    '<?xml version="1.0" encoding="utf-8" ?>'
    '<!DOCTYPE tv SYSTEM "xmltv.dtd"><tv generator-info-name="test">',
  );
  for (var c = 0; c < channels; c++) {
    out.write(
      '<channel id="c$c.fr"><display-name>C $c</display-name></channel>',
    );
  }
  final desc = 'Résumé d&apos;un épisode ' * (descLength ~/ 25 + 1);
  final first = now.subtract(const Duration(hours: 25));
  for (var c = 0; c < channels; c++) {
    for (var i = 0; i < perChannel; i++) {
      final start = first.add(Duration(minutes: 140 * i));
      out.write(
        '<programme start="${_date(start)}" '
        'stop="${_date(start.add(const Duration(minutes: 140)))}" '
        'channel="c$c.fr"><title>Programme $i de C $c</title>'
        '<desc>${desc.substring(0, descLength)}</desc></programme>',
      );
    }
  }
  out.write('</tv>');
  return out.toString();
}

void main() {
  late Directory dir;
  late FakeAdapter server;
  late DateTime now;
  late String body;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('couchplay_guide_');
    now = DateTime.now().toUtc();
    body = _guide(now);
    server = FakeAdapter(
      (options) async => options.uri.path == '/xmltv.php'
          ? ResponseBody.fromString(body, 200)
          : ResponseBody.fromString('', 404),
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  GuideRepository repository() => GuideRepository(
    ServerClient(
      host: 'http://example.com',
      username: 'u',
      password: 'p',
      userAgent: 'test',
      adapter: server,
    ),
    CatalogCache(dir, serverKey: 'serveur-a'),
    now: () => now,
  );

  File cacheFile() => File('${dir.path}/guide.json');

  test(
    'le compteur de lectures voit une lecture faite dans cet isolate',
    () async {
      final before = guideReadsInThisIsolate;
      await readGuide(
        Stream.value(const [60, 116, 118, 47, 62]),
        channels: const {},
        now: now,
      );
      expect(guideReadsInThisIsolate, before + 1);
    },
  );

  test('premier chargement : xmltv.php lu dans un isolate, puis mis en cache', () async {
    final before = guideReadsInThisIsolate;
    final loaded = await repository().guide({'c0.fr', 'c2.fr', 'absente.fr'});

    // D-081 : une lecture sur le fil de l'interface ferait monter ce compteur.
    expect(guideReadsInThisIsolate, before);
    expect(server.last!.uri.path, '/xmltv.php');
    expect(loaded.offline, isFalse);
    expect(loaded.value.channels, {'c0.fr', 'c2.fr', 'absente.fr'});
    expect(loaded.value.programmes.keys, unorderedEquals(['c0.fr', 'c2.fr']));
    expect(loaded.value.nowNext('c0.fr', now).current, isNotNull);
    expect(cacheFile().existsSync(), isTrue);
    expect(File('${dir.path}/guide.json.part').existsSync(), isFalse);
  });

  test('cache récent qui couvre les chaînes : aucun appel réseau, même '
      'pour une partie d’entre elles', () async {
    await repository().guide({'c0.fr', 'c1.fr'});
    final loaded = await repository().guide({'c1.fr'});
    expect(server.calls, 1);
    expect(loaded.savedAt, isNotNull);
    // Le cache garde ce qu'il avait, sans relire le serveur.
    expect(loaded.value.programmes.keys, unorderedEquals(['c0.fr', 'c1.fr']));
  });

  test('une chaîne de plus que le cache : retéléchargé', () async {
    await repository().guide({'c0.fr'});
    final loaded = await repository().guide({'c0.fr', 'c1.fr'});
    expect(server.calls, 2);
    expect(loaded.value.programmes.keys, unorderedEquals(['c0.fr', 'c1.fr']));
  });

  test('« Actualiser » ou cache de plus de 24 h : retour au serveur', () async {
    await repository().guide({'c0.fr'});
    await repository().guide({'c0.fr'}, refresh: true);
    expect(server.calls, 2);
    now = now.add(const Duration(hours: 25));
    await repository().guide({'c0.fr'});
    expect(server.calls, 3);
  });

  test('serveur muet avec un cache périmé : le cache, hors ligne', () async {
    await repository().guide({'c0.fr'});
    now = now.add(const Duration(days: 3));
    server = FakeAdapter.failing(DioExceptionType.connectionTimeout);
    final loaded = await repository().guide({'c0.fr', 'c1.fr'});
    expect(loaded.offline, isTrue);
    expect(loaded.savedAt, isNotNull);
    expect(loaded.value.programmes.keys, ['c0.fr']);
  });

  test('serveur muet sans cache : l’erreur remonte', () async {
    server = FakeAdapter.failing(DioExceptionType.connectionError);
    await expectLater(
      repository().guide({'c0.fr'}),
      throwsA(isA<ServerUnreachable>()),
    );
  });

  test(
    'guide coupé ou illisible : erreur, ni cache ni fichier téléchargé',
    () async {
      for (final text in [body.substring(0, body.length ~/ 2), '{"a":1}']) {
        body = text;
        await expectLater(
          repository().guide({'c0.fr'}),
          throwsA(isA<InvalidResponse>()),
        );
        expect(cacheFile().existsSync(), isFalse);
        expect(File('${dir.path}/guide.json.part').existsSync(), isFalse);
      }
    },
  );

  test('cache abîmé : relu comme absent, retéléchargé', () async {
    await repository().guide({'c0.fr'});
    cacheFile().writeAsStringSync('{"version":1,"channels":');
    final loaded = await repository().guide({'c0.fr'});
    expect(server.calls, 2);
    expect(loaded.value.programmes.keys, ['c0.fr']);
  });

  test('deux demandes ensemble : un seul téléchargement à la fois', () async {
    final gate = Completer<void>();
    final inner = server;
    var running = 0;
    var most = 0;
    server = FakeAdapter((options) async {
      most = ++running > most ? running : most;
      await gate.future;
      running--;
      return inner.fetch(options, null, null);
    });
    final repo = repository();
    final first = repo.guide({'c0.fr'});
    final second = repo.guide({'c0.fr'});
    gate.complete();
    await Future.wait([first, second]);
    expect(most, 1);
    // Le second a trouvé le cache du premier.
    expect(server.calls, 1);
  });

  test('guide de la taille du vrai (87 000 programmes, ~30 Mo) : chaînes '
      'visibles seules, cache de quelques Mo', () async {
    body = _guide(now, channels: 2574, perChannel: 34, descLength: 200);
    final visible = {for (var c = 0; c < 500; c++) 'c$c.fr'};
    final watch = Stopwatch()..start();
    final loaded = await repository().guide(visible);
    final elapsed = watch.elapsed;

    final kept = loaded.value.programmes.values.fold(0, (n, l) => n + l.length);
    // Fini après maintenant − 2 h : 25 des 34 programmes de chaque chaîne.
    expect(kept, 500 * 25);
    expect(loaded.value.programmes, hasLength(500));
    expect(cacheFile().lengthSync(), lessThan(5 * 1000 * 1000));
    // Borne large : une machine chargée ne doit pas rendre le test rouge.
    expect(elapsed, lessThan(const Duration(seconds: 60)));
  });
}
