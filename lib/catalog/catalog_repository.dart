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
    // Envoyée à l'isolate : elle ne capture que `kind`, pas le dépôt.
    (text) => parseCatalogItems(text, kind),
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

  Future<Loaded<T>> _load<T>(
    String name,
    Future<String> Function() fetch,
    T Function(String) parse, {
    required bool refresh,
  }) async {
    final cached = await _cache.read(name);
    if (cached != null &&
        !refresh &&
        _now().difference(cached.savedAt) < maxAge) {
      if (await _tryDecode(cached.text, parse) case final value?) {
        return Loaded(value, savedAt: cached.savedAt);
      }
    }

    final String text;
    try {
      text = await fetch();
    } on ServerException catch (e) {
      final offline = e is ServerUnreachable || e is ServerTimeout;
      if (offline && cached != null) {
        if (await _tryDecode(cached.text, parse) case final value?) {
          return Loaded(value, offline: true, savedAt: cached.savedAt);
        }
      }
      rethrow;
    }
    final value = await _decode(text, parse);
    await _cache.write(name, text);
    return Loaded(value);
  }

  /// Décode dans un isolate ; une réponse illisible devient [InvalidResponse].
  static Future<T> _decode<T>(String text, T Function(String) parse) async {
    try {
      return await Isolate.run(() => parse(text));
    } on FormatException {
      log('Catalogue', error: 'JSON invalide');
      throw const InvalidResponse('JSON invalide');
    }
  }

  // Cache corrompu : ignoré, comme s'il n'existait pas.
  static Future<T?> _tryDecode<T>(String text, T Function(String) parse) async {
    try {
      return await _decode(text, parse);
    } on InvalidResponse {
      return null;
    }
  }
}
