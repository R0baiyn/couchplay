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

  group('fetchPoster', () {
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, ...List.filled(20, 9)]);
    // URL de test construite : hôte, port et chemin ne doivent jamais
    // ressortir dans la cause.
    const host = 'images-secrets.example';
    const port = 8443;
    const path = 'chemin-secret/affiche.jpg';
    final url = Uri.parse('https://$host:$port/$path');

    Future<({Uint8List? bytes, String? cause})> poster(
      Future<ResponseBody> Function(RequestOptions) reply, {
      int limit = posterLimit,
      Duration timeout = posterTimeout,
      Uri? at,
    }) => fetchPoster(
      Dio()..httpClientAdapter = _PosterAdapter(reply),
      at ?? url,
      CancelToken(),
      limit: limit,
      timeout: timeout,
    );

    test('image reçue : octets, aucune cause', () async {
      final result = await poster(
        (_) async => ResponseBody.fromBytes(jpeg, 200),
      );

      expect(result.bytes, jpeg);
      expect(result.cause, isNull);
    });

    final failures =
        <(String, String, Future<ResponseBody> Function(RequestOptions))>[
          (
            'certificat refusé',
            'HandshakeException',
            (_) async =>
                throw HandshakeException('CERTIFICATE_VERIFY_FAILED $url'),
          ),
          (
            'certificat refusé',
            'badCertificate',
            (o) async => throw DioException.badCertificate(requestOptions: o),
          ),
          (
            'délai dépassé',
            'connectionTimeout',
            (o) async => throw DioException.connectionTimeout(
              requestOptions: o,
              timeout: const Duration(seconds: 1),
            ),
          ),
          (
            'délai dépassé',
            'receiveTimeout',
            (o) async => throw DioException.receiveTimeout(
              requestOptions: o,
              timeout: const Duration(seconds: 1),
            ),
          ),
          (
            'connexion coupée',
            'SocketException',
            (_) async => throw SocketException('Connection refused $url'),
          ),
          (
            'connexion coupée',
            'connectionError',
            (o) async => throw DioException.connectionError(
              requestOptions: o,
              reason: 'refusée $url',
            ),
          ),
          (
            'connexion coupée',
            'coupée en route',
            (_) async =>
                ResponseBody(Stream.error(HttpException('coupée $url')), 200),
          ),
          (
            'réponse HTTP 404',
            '404',
            (_) async => ResponseBody.fromString('', 404),
          ),
          (
            'réponse HTTP 503',
            '503',
            (_) async => ResponseBody.fromString('', 503),
          ),
          (
            'pas une image',
            'page HTML',
            (_) async =>
                ResponseBody.fromString('<html>erreur $url</html>', 200),
          ),
        ];
    for (final (cause, name, reply) in failures) {
      test('$name : « $cause », sans hôte, port ni chemin', () async {
        final result = await poster(reply);

        expect(result.bytes, isNull);
        expect(result.cause, cause);
        for (final secret in [host, '$port', 'chemin-secret']) {
          expect(result.cause, isNot(contains(secret)));
        }
      });
    }

    test('trop grosse : « image trop grosse »', () async {
      final result = await poster(
        (_) async => ResponseBody.fromBytes(jpeg, 200),
        limit: 10,
      );

      expect(result.bytes, isNull);
      expect(result.cause, 'image trop grosse');
    });

    test('envoi trop lent : « délai dépassé »', () async {
      final result = await poster(
        (_) async => ResponseBody(() async* {
          yield jpeg;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          yield jpeg;
        }(), 200),
        timeout: const Duration(milliseconds: 10),
      );

      expect(result.bytes, isNull);
      expect(result.cause, 'délai dépassé');
    });

    test(
      "adresse qui n'est pas http(s) : « adresse non prise en charge »",
      () async {
        final result = await poster(
          (_) async => fail('aucune requête attendue'),
          at: Uri.parse('file:///etc/passwd'),
        );

        expect(result.bytes, isNull);
        expect(result.cause, 'adresse non prise en charge');
      },
    );
  });
}

/// Adaptateur dio qui répond par [reply].
final class _PosterAdapter implements HttpClientAdapter {
  _PosterAdapter(this.reply);

  final Future<ResponseBody> Function(RequestOptions) reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => reply(options);

  @override
  void close({bool force = false}) {}
}
