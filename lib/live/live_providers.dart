import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable, setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/account_files.dart';
import '../accounts/account_store.dart';
import '../accounts/server_session.dart';
import '../catalog/catalog_cache.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/catalog_settings.dart';
import '../library/library.dart';
import '../library/library_store.dart';
import '../logging.dart';
import '../server/models.dart';
import '../server/server_client.dart';
import 'channel.dart';
import 'guide.dart';
import 'guide_layout.dart';
import 'guide_repository.dart';
import 'live_repository.dart';

/// Cache du direct du compte actif, `accounts/<id>/live/`, effacé avec le
/// compte. Un seul pour les chaînes et le guide : deux caches sur un même
/// dossier pourraient l'effacer l'un après l'autre au premier accès.
final _liveCacheProvider = Provider.autoDispose<CatalogCache>((ref) {
  final access = ref.watch(
    activeAccountProvider.select(
      (a) => a == null ? null : (a.id, a.host, a.username),
    ),
  );
  if (access == null) throw StateError('Aucun compte actif');
  final (id, host, username) = access;
  return CatalogCache(
    Directory(ref.watch(accountFilesProvider).path(id, 'live')),
    serverKey: serverKeyOf(host, username),
  );
});

ServerClient _client(Ref ref) =>
    ref.watch(serverClientProvider) ?? (throw StateError('Aucun compte actif'));

/// Direct du compte actif ; change avec le compte ou ses accès.
final liveRepositoryProvider = Provider.autoDispose<LiveRepository>(
  (ref) => LiveRepository(_client(ref), ref.watch(_liveCacheProvider)),
);

/// Guide des programmes du compte actif, dans le même dossier.
final guideRepositoryProvider = Provider.autoDispose<GuideRepository>(
  (ref) => GuideRepository(_client(ref), ref.watch(_liveCacheProvider)),
);

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

  /// Chaînes par id : pour retrouver une favorite.
  late final Map<String, Channel> byId = {
    for (final channel in channels) channel.id: channel,
  };
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
/// inconnue. [favoritesCategory] : les chaînes favorites (liste, grille et
/// zapping restent dans les favorites).
final liveChannelsProvider = Provider.autoDispose
    .family<AsyncValue<List<Channel>>, String>((ref, categoryId) {
      if (categoryId == favoritesCategory.id) {
        return ref.watch(favoriteChannelsProvider);
      }
      return ref
          .watch(liveCatalogProvider)
          .whenData(
            (loaded) => loaded.value.byCategory[categoryId] ?? const [],
          );
    });

/// Entrée « Favorites » en tête du choix de catégorie de l'onglet TV. Son id
/// n'est pas un nombre : aucune catégorie du serveur ne le prend.
const favoritesCategory = Category(id: 'favorites', name: 'Favorites');

/// Chaînes favorites du compte, triées par `num` (sans numéro à la fin, dans
/// l'ordre d'ajout). Une chaîne encore au catalogue en garde toutes les
/// données (guide, catégorie), même masquée par le filtre ; une chaîne qui
/// n'y est plus reste affichée telle qu'enregistrée, pour pouvoir la retirer.
/// Sans valeur pendant un rechargement ou après un échec (`whenData`) :
/// jamais les favorites d'un compte complétées par le catalogue de l'ancien.
final favoriteChannelsProvider =
    Provider.autoDispose<AsyncValue<List<Channel>>>((ref) {
      final saved = ref.watch(
        libraryProvider.select((l) => l.channelFavorites),
      );
      return ref.watch(liveCatalogProvider).whenData((loaded) {
        final channels = [
          for (final channel in saved)
            loaded.value.byId[channel.id] ?? channelOf(channel),
        ];
        return sortedByNumber(channels);
      });
    });

/// Catégories de l'onglet TV : « Favorites » s'il y en a, puis les visibles.
final liveTabCategoriesProvider =
    Provider.autoDispose<AsyncValue<List<Category>>>((ref) {
      final hasFavorites = ref.watch(
        libraryProvider.select((l) => l.channelFavorites.isNotEmpty),
      );
      return ref
          .watch(visibleLiveCategoriesProvider)
          .whenData(
            (visible) => [if (hasFavorites) favoritesCategory, ...visible],
          );
    });

/// Une chaîne de `library.json`, de quoi l'afficher et la lire (sans guide).
Channel channelOf(SavedChannel saved) => Channel(
  id: saved.id,
  name: saved.name,
  number: saved.number,
  logo: saved.logo,
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

/// Ids du guide (`epg_channel_id`) des chaînes ; égaux si les ids le sont :
/// un catalogue rechargé à l'identique ne relit pas le guide.
@immutable
final class _GuideChannels {
  const _GuideChannels(this.ids);

  final Set<String> ids;

  @override
  bool operator ==(Object other) =>
      other is _GuideChannels && setEquals(other.ids, ids);

  @override
  int get hashCode => Object.hashAllUnordered(ids);
}

/// Toutes les chaînes du catalogue, visibles ou non : le filtre des
/// catégories ne fait que choisir quoi afficher, sans jamais retélécharger
/// le guide (un guide entier par case cochée, chez un fournisseur qui peut
/// bannir). Mesuré sur un vrai guide : 2 711 ids, cache de 7,4 Mo, lu en
/// 1 s. `null` tant que les chaînes du compte ne sont pas là (chargement ou
/// erreur) : riverpod y garde la valeur d'avant, celle de l'ancien compte
/// après un changement de compte, et le guide du nouveau serait demandé
/// avec les chaînes de l'ancien.
final _guideChannelsProvider = Provider.autoDispose<_GuideChannels?>((ref) {
  final channels = ref
      .watch(liveCatalogProvider)
      .unwrapPrevious()
      .value
      ?.value
      .channels;
  if (channels == null) return null;
  return _GuideChannels({
    for (final channel in channels) ?channel.epgChannelId,
  });
});

/// Guide des chaînes du catalogue. Ne finit jamais en erreur : sans guide
/// (serveur muet, pas de guide, guide illisible), une ligne de journal et un
/// guide vide ; les chaînes restent utilisables.
final guideProvider =
    AsyncNotifierProvider.autoDispose<GuideNotifier, Loaded<Guide>>(
      GuideNotifier.new,
      // Pas de nouvel essai automatique : 30 Mo par essai.
      retry: noRetry,
    );

class GuideNotifier extends AsyncNotifier<Loaded<Guide>> {
  /// Écart minimal entre deux rechargements automatiques : hors ligne, un
  /// cache vieux de plusieurs jours ne relance pas un essai à chaque instant.
  static const _minReload = Duration(hours: 1);

  /// Relit le guide quand il a 24 h, même si l'écran reste ouvert (une TV
  /// laissée allumée), ou réessaie après un échec.
  Timer? _reload;

  @override
  Future<Loaded<Guide>> build() async {
    ref.onDispose(() => _reload?.cancel());
    final shown = state.value;
    final channels = ref.watch(_guideChannelsProvider);
    if (channels == null) return const Loaded(Guide.empty);
    final repository = ref.watch(guideRepositoryProvider);
    final loaded = await _loadGuide(repository, channels.ids);
    if (loaded != null) {
      if (ref.mounted) _scheduleReload(loaded);
      return loaded;
    }
    // Échec (1er chargement, rechargement des 24 h) : le guide affiché
    // reste, et un nouvel essai part dans une heure. Jamais celui d'un autre
    // compte : au changement de compte, les chaînes passent par `null`, qui
    // vide le guide avant le chargement du nouveau.
    if (ref.mounted) _arm(_minReload);
    return shown ?? const Loaded(Guide.empty);
  }

  /// « Actualiser » : retélécharge, même avec un cache récent. En cas
  /// d'échec, le guide affiché reste.
  Future<void> refresh() async {
    final channels = ref.read(_guideChannelsProvider);
    if (channels == null) return;
    final repository = ref.read(guideRepositoryProvider);
    final loaded = await _loadGuide(repository, channels.ids, refresh: true);
    if (loaded == null || !ref.mounted) return;
    state = AsyncData(loaded);
    _scheduleReload(loaded);
  }

  /// Rechargement quand le guide aura l'âge du cache (24 h depuis son
  /// téléchargement), au plus tôt dans [_minReload].
  void _scheduleReload(Loaded<Guide> loaded) {
    final now = ref.read(guideNowProvider)();
    final delay = (loaded.savedAt ?? now)
        .add(CatalogRepository.maxAge)
        .difference(now);
    _arm(delay < _minReload ? _minReload : delay);
  }

  void _arm(Duration delay) {
    _reload?.cancel();
    _reload = Timer(delay, ref.invalidateSelf);
  }
}

/// `null` si le guide n'a pas pu être lu (une ligne de journal).
Future<Loaded<Guide>?> _loadGuide(
  GuideRepository repository,
  Set<String> channels, {
  bool refresh = false,
}) async {
  try {
    return await repository.guide(channels, refresh: refresh);
  } on Exception catch (e) {
    // Les messages des erreurs du serveur ne contiennent ni URL ni
    // identifiants ; des autres, seul le type.
    log(
      'Guide des programmes indisponible',
      error: e is ServerException ? e.message : e.runtimeType,
    );
    return null;
  }
}

/// Horloge du guide (tests : horloge factice).
final guideNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Heure à laquelle lire « en cours » : avancée à chaque changement de
/// programme et chaque minute (barres d'avancement). Une seule minuterie pour
/// tous les écrans qui l'écoutent, aucune sans guide.
final guideClockProvider = NotifierProvider.autoDispose<GuideClock, DateTime>(
  GuideClock.new,
);

final class GuideClock extends Notifier<DateTime> {
  static const _tick = Duration(minutes: 1);

  Timer? _timer;

  @override
  DateTime build() {
    final guide = ref.watch(guideProvider).value?.value ?? Guide.empty;
    final now = ref.watch(guideNowProvider);
    ref.onDispose(() => _timer?.cancel());
    final at = now();
    _schedule(guide, now, at);
    return at;
  }

  void _schedule(Guide guide, DateTime Function() now, DateTime at) {
    _timer?.cancel();
    if (guide.programmes.isEmpty) return;
    var delay = _tick;
    if (guide.nextChange(at) case final change?
        when change.difference(at) < delay) {
      delay = change.difference(at);
    }
    _timer = Timer(delay, () {
      final next = now();
      state = next;
      _schedule(guide, now, next);
    });
  }
}

/// Ce que passe une chaîne : programme en cours (et sa part écoulée, de 0 à
/// 1), puis le suivant.
typedef OnAir = ({Programme? current, double progress, Programme? next});

/// Ce que passe la chaîne d'id de guide [epgChannelId] ; `null` si le guide
/// n'en dit rien (pas de programme, guide pas encore lu).
final onAirProvider = Provider.autoDispose.family<OnAir?, String>((
  ref,
  epgChannelId,
) {
  final guide = ref.watch(guideProvider).value?.value;
  if (guide == null) return null;
  final at = ref.watch(guideClockProvider);
  final (:current, :next) = guide.nowNext(epgChannelId, at);
  if (current == null && next == null) return null;
  return (current: current, progress: current?.progress(at) ?? 0, next: next);
});

/// Mise en page de la grille des programmes d'une catégorie. L'axe part de
/// l'heure de la première lecture (maintenant − 2 h) : il ne glisse pas à
/// chaque minute, seulement quand le guide ou les chaînes changent.
final guideLayoutProvider = Provider.autoDispose.family<GuideLayout, String>((
  ref,
  categoryId,
) {
  final channels =
      ref.watch(liveChannelsProvider(categoryId)).value ?? const <Channel>[];
  final guide = ref.watch(guideProvider).value?.value ?? Guide.empty;
  return GuideLayout.of(channels, guide, ref.read(guideNowProvider)());
});
