import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/account_files.dart';
import '../accounts/account_store.dart';
import '../accounts/server_session.dart';
import '../server/models.dart';
import 'catalog_cache.dart';
import 'catalog_repository.dart';

/// Catalogue du compte actif ; change avec le compte ou ses accès.
final catalogRepositoryProvider = Provider.autoDispose<CatalogRepository>((
  ref,
) {
  final client = ref.watch(serverClientProvider);
  final id = ref.watch(activeAccountProvider.select((a) => a?.id));
  if (client == null || id == null) throw StateError('Aucun compte actif');
  return CatalogRepository(
    client,
    CatalogCache(ref.watch(accountFilesProvider).of(id)),
  );
});

// Pas de nouvelle tentative automatique (Riverpod 3 en fait par défaut) :
// l'écran propose « Réessayer », et le mode hors ligne prend le relais.
Duration? _noRetry(int _, Object _) => null;

final categoriesProvider = AsyncNotifierProvider.autoDispose
    .family<CategoriesNotifier, Loaded<List<Category>>, ContentKind>(
      CategoriesNotifier.new,
      retry: _noRetry,
    );

final class CategoriesNotifier extends AsyncNotifier<Loaded<List<Category>>> {
  CategoriesNotifier(this.kind);

  final ContentKind kind;

  @override
  Future<Loaded<List<Category>>> build() =>
      ref.watch(catalogRepositoryProvider).categories(kind);

  /// « Actualiser » : ignore le cache, même récent.
  Future<void> refresh() async {
    final repository = ref.read(catalogRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => repository.categories(kind, refresh: true),
    );
  }
}

/// Films ou séries d'une catégorie.
final itemsProvider = AsyncNotifierProvider.autoDispose
    .family<ItemsNotifier, Loaded<List<CatalogItem>>, (ContentKind, String)>(
      ItemsNotifier.new,
      retry: _noRetry,
    );

final class ItemsNotifier extends AsyncNotifier<Loaded<List<CatalogItem>>> {
  ItemsNotifier(this.key);

  final (ContentKind, String) key;

  @override
  Future<Loaded<List<CatalogItem>>> build() =>
      ref.watch(catalogRepositoryProvider).items(key.$1, key.$2);

  Future<void> refresh() async {
    final repository = ref.read(catalogRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => repository.items(key.$1, key.$2, refresh: true),
    );
  }
}

final movieDetailsProvider = FutureProvider.autoDispose
    .family<MovieDetails, String>(
      (ref, id) => ref.watch(catalogRepositoryProvider).movie(id),
      retry: _noRetry,
    );

final seriesDetailsProvider = FutureProvider.autoDispose
    .family<SeriesDetails, String>(
      (ref, id) => ref.watch(catalogRepositoryProvider).series(id),
      retry: _noRetry,
    );
