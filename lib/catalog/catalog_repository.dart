import 'dart:isolate';

import '../logging.dart';
import '../server/models.dart';
import '../server/server_client.dart';
import 'catalog_cache.dart';

/// Résultat d'un chargement du catalogue.
final class Loaded<T> {
  const Loaded(this.value, {this.offline = false, this.savedAt});

  final T value;

  /// Le serveur n'a pas répondu : [value] vient d'un cache périmé.
  final bool offline;

  /// Date des données quand elles viennent du cache.
  final DateTime? savedAt;
}

/// Catalogue d'un compte : serveur, cache disque et décodage hors du thread
/// de l'interface.
///
/// Un cache de moins de [maxAge] sert sans appel réseau. Plus vieux, ou à la
/// demande (`refresh`), le serveur est interrogé ; s'il est injoignable, le
/// cache sert quand même, marqué hors ligne.
final class CatalogRepository {
  CatalogRepository(
    this._client,
    this._cache, {
    this.maxAge = const Duration(hours: 24),
    this._now = DateTime.now,
  });

  final ServerClient _client;
  final CatalogCache _cache;
  final Duration maxAge;
  final DateTime Function() _now;

  Future<Loaded<List<Category>>> categories(
    ContentKind kind, {
    bool refresh = false,
  }) => _load(
    '${kind.name}_categories',
    () => _client.fetch(kind.categoriesAction),
    parseCategories,
    refresh: refresh,
  );

  Future<Loaded<List<CatalogItem>>> items(
    ContentKind kind,
    String categoryId, {
    bool refresh = false,
  }) => _load(
    '${kind.name}_list_$categoryId',
    () => _client.fetch(kind.listAction, {'category_id': categoryId}),
    switch (kind) {
      ContentKind.movies => _parseMovies,
      ContentKind.series => _parseSeries,
    },
    refresh: refresh,
  );

  /// Fiches : pas de cache, elles sont petites et ouvertes une à une.
  Future<MovieDetails> movie(String id) async => _decode(
    await _client.fetch('get_vod_info', {'vod_id': id}),
    parseMovieDetails,
  );

  Future<SeriesDetails> series(String id) async => _decode(
    await _client.fetch('get_series_info', {'series_id': id}),
    parseSeriesDetails,
  );

  /// [parse] doit être une fonction de premier niveau : elle part dans un
  /// isolate, et une fermeture déclarée ici emporterait le dépôt, son client
  /// http et ses connexions, impossibles à y envoyer.
  Future<Loaded<T>> _load<T>(
    String name,
    Future<String> Function() fetch,
    T Function(String) parse, {
    required bool refresh,
  }) async {
    final path = _cache.path(name);
    final savedAt = path == null ? null : await _cache.savedAt(path);
    final fresh = savedAt != null && _now().difference(savedAt) < maxAge;
    if (path != null && fresh && !refresh) {
      if (await _readCached(path, parse) case final value?) {
        return Loaded(value, savedAt: savedAt);
      }
    }

    final String text;
    try {
      text = await fetch();
    } on ServerException catch (e) {
      final offline = e is ServerUnreachable || e is ServerTimeout;
      if (offline && path != null && savedAt != null) {
        if (await _readCached(path, parse) case final value?) {
          return Loaded(value, offline: true, savedAt: savedAt);
        }
      }
      rethrow;
    }
    return Loaded(await _decodeAndStore(text, parse, path));
  }
}

List<CatalogItem> _parseMovies(String text) =>
    parseCatalogItems(text, ContentKind.movies);

List<CatalogItem> _parseSeries(String text) =>
    parseCatalogItems(text, ContentKind.series);

// Fonctions de premier niveau : ce qu'elles envoient à l'isolate se limite
// à leurs paramètres.

Future<T> _decode<T>(String text, T Function(String) parse) async {
  try {
    return await Isolate.run(() => parse(text));
  } on FormatException {
    log('Catalogue', error: 'JSON invalide : ${_preview(text)}');
    throw const InvalidResponse('JSON invalide');
  }
}

/// Décode puis met en cache, dans l'isolate : le texte n'est ni décodé ni
/// réencodé sur le thread de l'interface. Rien n'est écrit s'il est illisible.
Future<T> _decodeAndStore<T>(
  String text,
  T Function(String) parse,
  String? path,
) async {
  final (T, bool) result;
  try {
    result = await Isolate.run(() {
      final value = parse(text);
      return (value, path == null || writeText(path, text));
    });
  } on FormatException {
    log('Catalogue', error: 'JSON invalide : ${_preview(text)}');
    throw const InvalidResponse('JSON invalide');
  }
  if (!result.$2) log('Cache du catalogue non écrit');
  return result.$1;
}

/// Cache illisible ou corrompu : `null`, comme s'il n'existait pas.
Future<T?> _readCached<T>(String path, T Function(String) parse) async {
  try {
    return await Isolate.run(() {
      final text = readText(path);
      return text == null ? null : parse(text);
    });
  } on FormatException {
    return null;
  }
}

/// Début d'une réponse illisible, pour les logs : une ligne, 120 caractères,
/// URL masquées (une page d'erreur peut recopier l'adresse demandée).
String _preview(String text) {
  final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final cut = line.length > 120 ? '${line.substring(0, 120)}…' : line;
  return line.isEmpty ? '(réponse vide, ${text.length} octets)' : redact(cut);
}
