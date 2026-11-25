import '../catalog/catalog_cache.dart';
import '../catalog/catalog_repository.dart';
import '../server/models.dart';
import '../server/server_client.dart';
import 'channel.dart';

/// Direct d'un compte : mêmes règles de cache que le catalogue
/// ([loadCached] : 24 h, cache périmé servi hors ligne, « Actualiser » qui
/// force), dans son propre dossier `accounts/<id>/live/`.
final class LiveRepository {
  LiveRepository(this._client, this._cache, {this._now = DateTime.now});

  final ServerClient _client;
  final CatalogCache _cache;
  final DateTime Function() _now;

  Future<Loaded<List<Category>>> categories({bool refresh = false}) =>
      loadCached(
        _cache,
        'live_categories',
        () => _client.fetch('get_live_categories'),
        parseCategories,
        refresh: refresh,
        now: _now,
      );

  /// Toutes les chaînes en une requête (plusieurs Mo pour certains
  /// fournisseurs), décodées dans un isolate.
  Future<Loaded<List<Channel>>> channels({bool refresh = false}) => loadCached(
    _cache,
    'live_streams',
    () => _client.fetch('get_live_streams'),
    parseChannels,
    refresh: refresh,
    now: _now,
  );
}
