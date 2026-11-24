import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Échec d'un transfert.
sealed class TransferException implements Exception {
  const TransferException();

  /// Raison prête à afficher.
  String get message;

  @override
  String toString() => message;
}

/// Coupure réseau, délai dépassé, fichier reçu incomplet : une nouvelle
/// tentative reprend où on en était.
final class TransferInterrupted extends TransferException {
  const TransferInterrupted();

  @override
  String get message => 'Connexion interrompue';
}

/// Le serveur refuse le fichier (403, 404…) : réessayer ne sert à rien.
final class TransferRefused extends TransferException {
  const TransferRefused(this.status);

  final int status;

  @override
  String get message => switch (status) {
    404 => 'Introuvable sur le serveur (404)',
    _ => 'Refusé par le serveur ($status)',
  };
}

/// Plus de place sur le disque, avant ou pendant le transfert.
final class NotEnoughSpace extends TransferException {
  const NotEnoughSpace();

  @override
  String get message => 'Espace disque insuffisant';
}

/// Le serveur envoie plus que la taille annoncée, ou une plage qui ne colle
/// pas deux fois de suite.
final class UnexpectedSize extends TransferException {
  const UnexpectedSize();

  @override
  String get message => 'Fichier reçu différent de celui annoncé';
}

/// Écriture impossible pour une autre raison (droits, disque retiré).
final class WriteFailed extends TransferException {
  const WriteFailed();

  @override
  String get message => "Écriture du fichier impossible";
}

/// Erreurs « disque plein » : ENOSPC (Linux, Android), ERROR_DISK_FULL et
/// ERROR_HANDLE_DISK_FULL (Windows).
const _diskFull = {28, 112, 39};

/// Télécharge [url] dans [part], en reprenant à la taille actuelle de
/// [part] (`Range: bytes=<taille>-`). Rend la taille totale du fichier une
/// fois [part] complet ; à l'appelant de le renommer.
///
/// [size] : taille connue d'un essai précédent, 0 sinon. [onProgress]
/// reçoit les octets présents dans [part] et la taille totale (0 si
/// inconnue). [freeSpace] rend la place libre du dossier de [part], `null`
/// si elle est inconnue. Annulé par [cancel] : le fichier est fermé avant
/// que le `Future` se termine, et [part] reste pour une reprise.
///
/// Les erreurs sont des [TransferException], ou une `DioException`
/// d'annulation. Aucune URL n'en sort : celle du flux porte les
/// identifiants.
Future<int> transfer({
  required Dio dio,
  required Uri url,
  required File part,
  required CancelToken cancel,
  int size = 0,
  void Function(int received, int size)? onProgress,
  Future<int?> Function(Directory directory)? freeSpace,
}) async {
  // Deux essais au plus : le second repart de zéro si le serveur ne
  // reprend pas où on lui demande.
  for (var attempt = 0; ; attempt++) {
    // La taille sur le disque fait foi : le manifeste peut avoir du retard
    // après un arrêt brutal.
    var offset = await part.exists() ? await part.length() : 0;
    if (size > 0 && offset == size) return size;
    if (size > 0 && offset > size) {
      await part.writeAsBytes(const [], flush: true);
      offset = 0;
    }
    final Response<ResponseBody> response;
    try {
      response = await dio.getUri<ResponseBody>(
        url,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          headers: {if (offset > 0) HttpHeaders.rangeHeader: 'bytes=$offset-'},
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw const TransferInterrupted();
    }
    final body = response.data!;
    final status = response.statusCode ?? 0;
    int start;
    int total;
    switch (status) {
      case 206:
        final range = _contentRange.firstMatch(
          response.headers.value(HttpHeaders.contentRangeHeader) ?? '',
        );
        start = int.tryParse(range?[1] ?? '') ?? -1;
        total = int.tryParse(range?[2] ?? '') ?? 0;
        if (start != offset) {
          // Plage inattendue : on repart de zéro, une fois.
          await _discard(body);
          if (attempt > 0) throw const UnexpectedSize();
          await part.writeAsBytes(const [], flush: true);
          continue;
        }
      case 200:
        // Le serveur ignore la plage : il renvoie tout, on repart de zéro.
        start = 0;
        total = _length(response) ?? 0;
      case 416 when offset > 0 && attempt == 0:
        // Plage refusée : le fichier a changé sur le serveur.
        await _discard(body);
        await part.writeAsBytes(const [], flush: true);
        continue;
      default:
        await _discard(body);
        throw TransferRefused(status);
    }
    if (total > 0 && freeSpace != null) {
      final free = await freeSpace(part.parent);
      if (free != null && free < total - start) {
        await _discard(body);
        throw const NotEnoughSpace();
      }
    }
    return _write(body, part, start, total, cancel, onProgress);
  }
}

final _contentRange = RegExp(r'^bytes (\d+)-\d+/(\d+)$');

int? _length(Response<Object?> response) {
  final value = int.tryParse(
    response.headers.value(HttpHeaders.contentLengthHeader) ?? '',
  );
  return value != null && value > 0 ? value : null;
}

/// Ferme une réponse dont on ne lit pas le corps.
Future<void> _discard(ResponseBody body) async {
  try {
    await body.stream.listen(null).cancel();
  } on Object {
    // Rien à faire : la connexion est déjà fermée.
  }
}

/// Écrit le corps à partir de [start] dans [part] ; rend [total] une fois
/// complet (ou la taille reçue si [total] est inconnu).
Future<int> _write(
  ResponseBody body,
  File part,
  int start,
  int total,
  CancelToken cancel,
  void Function(int received, int size)? onProgress,
) async {
  final RandomAccessFile file;
  try {
    file = await part.open(mode: start == 0 ? FileMode.write : FileMode.append);
  } on FileSystemException catch (e) {
    await _discard(body);
    throw _writeError(e);
  }
  var received = start;
  try {
    await for (final chunk in body.stream) {
      received += chunk.length;
      if (total > 0 && received > total) throw const UnexpectedSize();
      await file.writeFrom(chunk);
      onProgress?.call(received, total);
    }
  } on FileSystemException catch (e) {
    throw _writeError(e);
  } on TransferException {
    rethrow;
  } on DioException catch (e) {
    if (CancelToken.isCancel(e)) rethrow;
    throw const TransferInterrupted();
  } on Exception {
    // HttpException, SocketException… : connexion coupée en route.
    if (cancel.isCancelled) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(),
        reason: cancel.cancelError?.error,
      );
    }
    throw const TransferInterrupted();
  } finally {
    // Fermé avant toute suite : sous Windows, un fichier ouvert ne se
    // renomme ni ne s'efface.
    await file.close();
  }
  if (cancel.isCancelled) {
    throw DioException.requestCancelled(
      requestOptions: RequestOptions(),
      reason: cancel.cancelError?.error,
    );
  }
  if (total > 0 && received < total) throw const TransferInterrupted();
  return total > 0 ? total : received;
}

TransferException _writeError(FileSystemException e) =>
    _diskFull.contains(e.osError?.errorCode)
    ? const NotEnoughSpace()
    : const WriteFailed();

/// Taille maximale d'une affiche : au-delà, elle n'est pas gardée.
const posterLimit = 4 << 20;

/// Durée maximale de la réception d'une affiche.
const posterTimeout = Duration(seconds: 30);

/// Lit l'affiche [url] en mémoire, [limit] octets au plus (comptés à la
/// réception : la taille annoncée peut mentir) et [timeout] au plus. Sans
/// octets (`bytes` nul) si l'URL n'est pas en http(s), si le serveur refuse
/// ou coupe, ou si l'image est trop grosse ou n'est pas une image (page
/// d'erreur, portail captif) : la vidéo se télécharge sans elle. `cause`
/// dit pourquoi, en mots, d'après les seuls types d'erreur : ni message
/// d'exception ni URL n'en sortent, celle d'un fournisseur peut porter des
/// identifiants.
Future<({Uint8List? bytes, String? cause})> fetchPoster(
  Dio dio,
  Uri url,
  CancelToken cancel, {
  int limit = posterLimit,
  Duration timeout = posterTimeout,
}) async {
  if (!url.isScheme('http') && !url.isScheme('https')) {
    return (bytes: null, cause: 'adresse non prise en charge');
  }
  try {
    final response = await dio.getUri<ResponseBody>(
      url,
      cancelToken: cancel,
      options: Options(responseType: ResponseType.stream),
    );
    final bytes = BytesBuilder(copy: false);
    final clock = Stopwatch()..start();
    await for (final chunk in response.data!.stream) {
      bytes.add(chunk);
      // Quitter la boucle ferme la connexion. La durée aussi est bornée :
      // un hôte qui envoie au compte-gouttes ne retient pas les suivantes.
      if (bytes.length > limit) {
        return (bytes: null, cause: 'image trop grosse');
      }
      if (clock.elapsed > timeout) {
        return (bytes: null, cause: 'délai dépassé');
      }
    }
    final image = bytes.takeBytes();
    return _isImage(image)
        ? (bytes: image, cause: null)
        : (bytes: null, cause: 'pas une image');
  } on DioException catch (e) {
    return (bytes: null, cause: _posterCause(e));
  } on Exception catch (e) {
    // HttpException, SocketException : connexion coupée en route.
    return (bytes: null, cause: _posterCause(e));
  }
}

/// La cause d'un échec d'affiche, lue sur les types seulement.
String _posterCause(Object? e) {
  if (e is DioException) {
    return switch (e.type) {
      DioExceptionType.badCertificate => 'certificat refusé',
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => 'délai dépassé',
      DioExceptionType.badResponse => 'réponse HTTP ${e.response?.statusCode}',
      DioExceptionType.cancel => 'annulée',
      DioExceptionType.connectionError ||
      DioExceptionType.unknown => _posterCause(e.error),
    };
  }
  return e is TlsException ? 'certificat refusé' : 'connexion coupée';
}

/// JPEG, PNG, GIF, WebP ou BMP, reconnus à leurs premiers octets.
bool _isImage(Uint8List b) {
  bool starts(List<int> magic, [int at = 0]) {
    if (b.length < at + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (b[at + i] != magic[i]) return false;
    }
    return true;
  }

  return starts(const [0xFF, 0xD8, 0xFF]) ||
      starts(const [0x89, 0x50, 0x4E, 0x47]) ||
      starts(const [0x47, 0x49, 0x46, 0x38]) ||
      starts(const [0x42, 0x4D]) ||
      (starts(const [0x52, 0x49, 0x46, 0x46]) &&
          starts(const [0x57, 0x45, 0x42, 0x50], 8));
}
