import 'dart:io';
import 'dart:typed_data';

import 'package:couchplay/downloads/transfer.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'video_server.dart';

void main() {
  late Directory root;
  late File part;
  final source = Uint8List.fromList(List.generate(1000, (i) => i % 251));

  setUp(() {
    root = Directory.systemTemp.createTempSync('couchplay_transfer_');
    part = File('${root.path}/movie-1.mkv.part');
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<int> run(VideoServer server, {int size = 0, CancelToken? cancel}) =>
      transfer(
        dio: server.dio,
        url: Uri.parse('http://serveur.test/film'),
        part: part,
        cancel: cancel ?? CancelToken(),
        size: size,
      );

  test('reprise : demande la suite et complète le fichier', () async {
    part.writeAsBytesSync(source.sublist(0, 400));
    final server = VideoServer(source);

    expect(await run(server), 1000);

    expect(server.ranges, ['bytes=400-']);
    expect(part.readAsBytesSync(), source);
  });

  test('coupure : interrompu, puis la reprise aboutit', () async {
    final server = VideoServer(source, cutAt: 600);

    await expectLater(run(server), throwsA(isA<TransferInterrupted>()));
    expect(part.lengthSync(), 600);

    server.cutAt = null;
    expect(await run(server, size: 1000), 1000);
    expect(server.ranges, [null, 'bytes=600-']);
    expect(part.readAsBytesSync(), source);
  });

  test('200 au lieu de 206 : repart de zéro', () async {
    part.writeAsBytesSync(List.filled(400, 7));
    final server = VideoServer(source, ignoreRange: true);

    expect(await run(server), 1000);

    expect(part.readAsBytesSync(), source);
  });

  test('plus d\'octets que la taille annoncée : refusé', () async {
    final server = VideoServer(source, announcedSize: 800);

    await expectLater(run(server), throwsA(isA<UnexpectedSize>()));
  });

  test('moins d\'octets que la taille annoncée : interrompu', () async {
    final server = VideoServer(source, announcedSize: 1200);

    await expectLater(run(server), throwsA(isA<TransferInterrupted>()));
    expect(part.lengthSync(), 1000);
  });

  test('fichier déjà complet : aucune requête', () async {
    part.writeAsBytesSync(source);
    final server = VideoServer(source);

    expect(await run(server, size: 1000), 1000);
    expect(server.ranges, isEmpty);
  });

  test('refus du serveur', () async {
    final server = VideoServer(source, status: 403);

    await expectLater(
      run(server),
      throwsA(isA<TransferRefused>().having((e) => e.status, 'status', 403)),
    );
  });

  test('place insuffisante : rien n\'est écrit', () async {
    final server = VideoServer(source);

    await expectLater(
      transfer(
        dio: server.dio,
        url: Uri.parse('http://serveur.test/film'),
        part: part,
        cancel: CancelToken(),
        freeSpace: (_) async => 999,
      ),
      throwsA(isA<NotEnoughSpace>()),
    );
    expect(part.existsSync(), isFalse);
  });

  test('annulé en route : fichier fermé, effaçable aussitôt', () async {
    final server = VideoServer(source, cutAt: 500, hangAtCut: true);
    final cancel = CancelToken();
    final done = run(server, cancel: cancel);
    await server.reachedCut;

    cancel.cancel();
    await expectLater(done, throwsA(isA<DioException>()));

    // Sous Windows, un fichier encore ouvert ne s'efface pas.
    part.deleteSync();
  });
}
