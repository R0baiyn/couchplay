import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Serveur de vidéo simulé pour dio : sert [source] avec les plages
/// demandées, par morceaux de 100 octets.
final class VideoServer implements HttpClientAdapter {
  VideoServer(
    this.source, {
    this.cutAt,
    this.hangAtCut = false,
    this.ignoreRange = false,
    this.announcedSize,
    this.status,
  }) {
    dio.httpClientAdapter = this;
  }

  final Uint8List source;

  /// Position où la connexion est coupée (erreur), ou reste pendue avec
  /// [hangAtCut] jusqu'à l'annulation.
  int? cutAt;
  final bool hangAtCut;

  /// Répond 200 avec tout le fichier, même à une demande de plage.
  final bool ignoreRange;

  /// Taille annoncée à la place de la vraie.
  final int? announcedSize;

  /// Ce code à chaque requête, sans corps.
  int? status;

  /// En-tête Range de chaque requête (`null` : sans plage).
  final ranges = <String?>[];
  final dio = Dio();

  final _reachedCut = Completer<void>();
  Future<void> get reachedCut => _reachedCut.future;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final range = options.headers[HttpHeaders.rangeHeader] as String?;
    ranges.add(range);
    if (status case final code?) {
      return ResponseBody.fromString('', code);
    }
    final start = ignoreRange || range == null
        ? 0
        : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
    final size = announcedSize ?? source.length;
    final controller = StreamController<Uint8List>();
    unawaited(_send(controller, start, cancelFuture));
    final partial = !ignoreRange && range != null;
    return ResponseBody(
      controller.stream,
      partial ? 206 : 200,
      headers: {
        HttpHeaders.contentLengthHeader: ['${size - start}'],
        if (partial)
          HttpHeaders.contentRangeHeader: ['bytes $start-${size - 1}/$size'],
      },
    );
  }

  Future<void> _send(
    StreamController<Uint8List> controller,
    int start,
    Future<void>? cancelFuture,
  ) async {
    var cancelled = false;
    unawaited(
      cancelFuture?.then((_) {
        cancelled = true;
        if (!controller.isClosed) {
          controller.addError(const HttpException('Connexion fermée'));
          controller.close();
        }
      }),
    );
    for (var i = start; i < source.length && !cancelled; i += 100) {
      await Future<void>.delayed(Duration.zero);
      if (cutAt case final cut? when i >= cut) {
        if (!_reachedCut.isCompleted) _reachedCut.complete();
        if (hangAtCut) return;
        controller.addError(const SocketException('Connexion coupée'));
        await controller.close();
        return;
      }
      final end = i + 100 > source.length ? source.length : i + 100;
      if (!cancelled) controller.add(Uint8List.sublistView(source, i, end));
    }
    if (!cancelled) await controller.close();
  }

  @override
  void close({bool force = false}) {}
}
