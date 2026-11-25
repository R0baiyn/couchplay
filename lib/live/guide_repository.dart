import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../accounts/account_files.dart';
import '../catalog/catalog_cache.dart';
import '../catalog/catalog_repository.dart';
import '../logging.dart';
import '../server/server_client.dart';
import 'guide.dart';

/// Guide des programmes d'un compte : `xmltv.php` téléchargé dans un fichier,
/// lu en flux dans un isolate, puis gardé en cache (`guide.json`, à côté des
/// chaînes) pour les seules chaînes demandées.
///
/// Même politique que le catalogue : un cache de moins de 24 h qui couvre les
/// chaînes demandées sert sans appel réseau ; sinon, ou à la demande
/// (`refresh`), le guide est retéléchargé ; serveur injoignable, le cache sert
/// quand même, marqué hors ligne.
class GuideRepository {
  GuideRepository(this._client, this._cache, {this._now = DateTime.now});

  final ServerClient _client;
  final CatalogCache _cache;
  final DateTime Function() _now;

  /// Un seul chargement à la fois : deux appels proches (filtre changé
  /// pendant un téléchargement) n'écrivent pas le même fichier ensemble, et
  /// le second trouve souvent le cache du premier.
  Future<void> _queue = Future.value();

  Future<Loaded<Guide>> guide(Set<String> channels, {bool refresh = false}) {
    final result = _queue.then((_) => _load(channels, refresh));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Loaded<Guide>> _load(Set<String> channels, bool refresh) async {
    // Nom fixe et sûr : jamais null.
    final path = _cache.path('guide')!;
    final savedAt = await _cache.savedAt(path);
    final fresh =
        savedAt != null &&
        _now().difference(savedAt) < CatalogRepository.maxAge;
    if (fresh && !refresh) {
      if (await _readCached(path) case final cached?
          when cached.covers(channels)) {
        return Loaded(cached, savedAt: savedAt);
      }
    }

    final download = '$path.part';
    try {
      await _client.downloadGuide(download);
    } on ServerException catch (e) {
      final offline = e is ServerUnreachable || e is ServerTimeout;
      if (offline && savedAt != null) {
        if (await _readCached(path) case final cached?) {
          return Loaded(cached, offline: true, savedAt: savedAt);
        }
      }
      rethrow;
    }
    return Loaded(await _readAndStore(download, path, channels, _now()));
  }
}

// Fonctions de premier niveau : ce qu'elles envoient à l'isolate se limite
// à leurs paramètres.

/// Lit le guide téléchargé [download] dans un isolate, le met en cache dans
/// [path], puis efface [download]. Rien n'est écrit s'il est illisible.
Future<Guide> _readAndStore(
  String download,
  String path,
  Set<String> channels,
  DateTime now,
) async {
  final watch = Stopwatch()..start();
  final (Guide, bool) result;
  try {
    // Suivi : une mise à jour Windows qui quitte l'app attend cette écriture
    // (SerialFileWriter.flushAll).
    result = await SerialFileWriter.track(
      Isolate.run(() async {
        try {
          final guide = await readGuideFile(
            download,
            channels: channels,
            now: now,
          );
          final text = jsonEncode(guide.toJson());
          return (guide, writeAtomically(path, text) == null);
        } finally {
          try {
            File(download).deleteSync();
          } on FileSystemException {
            // Déjà effacé : rien à faire.
          }
        }
      }),
    );
  } on FormatException catch (e) {
    log('Guide des programmes illisible', error: e.message);
    throw const InvalidResponse('guide illisible');
  }
  final (guide, written) = result;
  final count = guide.programmes.values.fold(0, (n, l) => n + l.length);
  log(
    'Guide des programmes : $count programmes, ${guide.programmes.length} '
    'chaînes, lu en ${watch.elapsedMilliseconds} ms',
  );
  if (!written) log('Cache du guide non écrit');
  return guide;
}

/// Cache illisible, abîmé ou d'une autre version : `null`.
Future<Guide?> _readCached(String path) async {
  try {
    return await Isolate.run(() {
      final text = readText(path);
      return text == null ? null : Guide.fromJson(jsonDecode(text));
    });
  } on FormatException {
    return null;
  }
}
