import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/account_files.dart';
import '../accounts/account_store.dart';
import '../accounts/server_session.dart';
import '../catalog/catalog_cache.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/catalog_settings.dart';
import '../server/models.dart';
import 'channel.dart';
import 'live_repository.dart';

/// Direct du compte actif ; change avec le compte ou ses accès. Son cache vit
/// dans `accounts/<id>/live/`, effacé avec le compte.
final liveRepositoryProvider = Provider.autoDispose<LiveRepository>((ref) {
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
  return LiveRepository(
    client,
    CatalogCache(
      Directory(ref.watch(accountFilesProvider).path(id, 'live')),
      serverKey: serverKeyOf(host, username),
    ),
  );
});

/// Catégories et chaînes d'un compte, telles que le serveur les donne.
final class LiveCatalog {
  LiveCatalog(this.categories, this.channels);

  final List<Category> categories;

  /// Triées par `num`.
  final List<Channel> channels;

  /// Chaînes de chaque catégorie, dans l'ordre de [channels] : calculé une
  /// fois, pas à chaque catégorie affichée.
  late final Map<String, List<Channel>> byCategory = () {
    final groups = <String, List<Channel>>{};
    for (final channel in channels) {
      if (channel.categoryId case final id?) {
        (groups[id] ??= []).add(channel);
      }
    }
    return groups;
  }();
}

final liveCatalogProvider =
    AsyncNotifierProvider.autoDispose<LiveCatalogNotifier, Loaded<LiveCatalog>>(
      LiveCatalogNotifier.new,
      retry: noRetry,
    );

final class LiveCatalogNotifier extends AsyncNotifier<Loaded<LiveCatalog>> {
  @override
  Future<Loaded<LiveCatalog>> build() =>
      _load(ref.watch(liveRepositoryProvider));

  /// « Actualiser » : ignore le cache, même récent. Comme pour le catalogue,
  /// un résultat arrivé après un changement de compte est jeté.
  Future<void> refresh() async {
    final repository = ref.read(liveRepositoryProvider);
    final result = await AsyncValue.guard(
      () => _load(repository, refresh: true),
    );
    if (ref.mounted) state = result;
  }
}

/// L'un après l'autre : une erreur du serveur remonte telle quelle (pas
/// enveloppée comme avec `Future.wait`), et le client espace déjà ses
/// requêtes.
Future<Loaded<LiveCatalog>> _load(
  LiveRepository repository, {
  bool refresh = false,
}) async {
  final categories = await repository.categories(refresh: refresh);
  final channels = await repository.channels(refresh: refresh);
  return Loaded(
    LiveCatalog(categories.value, channels.value),
    offline: categories.offline || channels.offline,
    savedAt: channels.savedAt ?? categories.savedAt,
  );
}

/// Catégories du direct que le filtre du compte laisse voir (pays, adulte,
/// exceptions `live:<id>`).
final visibleLiveCategoriesProvider =
    Provider.autoDispose<AsyncValue<List<Category>>>((ref) {
      final filter = ref.watch(catalogFilterProvider);
      return ref
          .watch(liveCatalogProvider)
          .whenData((loaded) => filter.applyLive(loaded.value.categories));
    });

/// Chaînes d'une catégorie, triées par `num` ; vide pour une catégorie
/// inconnue.
final liveChannelsProvider = Provider.autoDispose
    .family<AsyncValue<List<Channel>>, String>(
      (ref, categoryId) => ref
          .watch(liveCatalogProvider)
          .whenData(
            (loaded) => loaded.value.byCategory[categoryId] ?? const [],
          ),
    );

/// Toutes les chaînes visibles, catégorie après catégorie : pour la
/// recherche et le zapping.
final visibleChannelsProvider = Provider.autoDispose<AsyncValue<List<Channel>>>(
  (ref) {
    final categories = ref.watch(visibleLiveCategoriesProvider);
    return ref
        .watch(liveCatalogProvider)
        .whenData(
          (loaded) => [
            for (final category in categories.value ?? const <Category>[])
              ...?loaded.value.byCategory[category.id],
          ],
        );
  },
);
