import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/account_files.dart';
import '../accounts/account_store.dart';
import '../accounts/server_session.dart';
import '../server/models.dart';
import 'catalog_cache.dart';
import 'catalog_repository.dart';
import 'versions.dart';

/// Catalogue du compte actif ; change avec le compte ou ses accès.
final catalogRepositoryProvider = Provider.autoDispose<CatalogRepository>((
  ref,
) {
  final client = ref.watch(serverClientProvider);
  final access = ref.watch(
    activeAccountProvider.select(
      (a) => a == null ? null : (a.id, a.host, a.username),
    ),
  );
  if (client == null || access == null) {
    throw StateError('Aucun compte actif');
  }
  final (id, host, username) = access;
  final folder = ref.watch(accountFilesProvider).of(id).path;
  return CatalogRepository(
    client,
    CatalogCache(
      Directory('$folder${Platform.pathSeparator}catalog'),
      serverKey: serverKeyOf(host, username),
    ),
  );
});

// Pas de nouvelle tentative automatique (Riverpod 3 en fait par défaut) :
// l'écran propose « Réessayer », et le mode hors ligne prend le relais.
Duration? noRetry(int _, Object _) => null;

final categoriesProvider = AsyncNotifierProvider.autoDispose
    .family<CategoriesNotifier, Loaded<List<Category>>, ContentKind>(
      CategoriesNotifier.new,
      retry: noRetry,
    );

final class CategoriesNotifier extends AsyncNotifier<Loaded<List<Category>>> {
  CategoriesNotifier(this.kind);

  final ContentKind kind;

  @override
  Future<Loaded<List<Category>>> build() =>
      ref.watch(catalogRepositoryProvider).categories(kind);

  /// « Actualiser » : ignore le cache, même récent. Les données affichées
  /// restent en place pendant le rechargement.
  Future<void> refresh() => _refreshWith(
    ref,
    (repository) => repository.categories(kind, refresh: true),
    (value) => state = value,
  );
}

/// Films ou séries d'une catégorie.
final itemsProvider = AsyncNotifierProvider.autoDispose
    .family<ItemsNotifier, Loaded<List<CatalogEntry>>, (ContentKind, String)>(
      ItemsNotifier.new,
      retry: noRetry,
    );

final class ItemsNotifier extends AsyncNotifier<Loaded<List<CatalogEntry>>> {
  ItemsNotifier(this.key);

  final (ContentKind, String) key;

  @override
  Future<Loaded<List<CatalogEntry>>> build() =>
      ref.watch(catalogRepositoryProvider).items(key.$1, key.$2);

  Future<void> refresh() => _refreshWith(
    ref,
    (repository) => repository.items(key.$1, key.$2, refresh: true),
    (value) => state = value,
  );
}

/// Recharge, puis publie le résultat seulement si le provider est toujours
/// celui qui a lancé la requête. Changer de compte pendant le rechargement
/// reconstruit le provider : le résultat de l'ancien compte est alors jeté,
/// au lieu de s'afficher sous le nouveau.
Future<void> _refreshWith<T>(
  Ref ref,
  Future<T> Function(CatalogRepository repository) load,
  void Function(AsyncValue<T> value) publish,
) async {
  final repository = ref.read(catalogRepositoryProvider);
  final result = await AsyncValue.guard(() => load(repository));
  if (ref.mounted) publish(result);
}

final movieDetailsProvider = FutureProvider.autoDispose
    .family<MovieDetails, String>(
      (ref, id) => ref.watch(catalogRepositoryProvider).movie(id),
      retry: noRetry,
    );

/// Fiche d'une série, gardée un jour en cache : pour l'accueil.
final cachedSeriesDetailsProvider = FutureProvider.autoDispose
    .family<SeriesDetails, String>(
      (ref, id) => ref.watch(catalogRepositoryProvider).cachedSeries(id),
      retry: noRetry,
    );

final seriesDetailsProvider = FutureProvider.autoDispose
    .family<SeriesDetails, String>(
      (ref, id) => ref.watch(catalogRepositoryProvider).series(id),
      retry: noRetry,
    );
