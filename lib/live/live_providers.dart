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
import '../logging.dart';
import '../server/models.dart';
import '../server/server_client.dart';
import 'channel.dart';
import 'guide.dart';
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

/// Ids du guide (`epg_channel_id`) des chaînes visibles ; égaux si les ids le
/// sont : un catalogue rechargé à l'identique ne relit pas le guide.
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

/// `null` tant que les chaînes ne sont pas chargées.
final _guideChannelsProvider = Provider.autoDispose<_GuideChannels?>((ref) {
  final channels = ref.watch(visibleChannelsProvider).value;
  if (channels == null) return null;
  return _GuideChannels({
    for (final channel in channels) ?channel.epgChannelId,
  });
});

/// Guide des chaînes visibles. Ne finit jamais en erreur : sans guide
/// (serveur muet, pas de guide, guide illisible), une ligne de journal et un
/// guide vide ; les chaînes restent utilisables. Un filtre qui ajoute des
/// chaînes absentes du cache relance un téléchargement, un filtre qui en
/// retire, non.
final guideProvider =
    AsyncNotifierProvider.autoDispose<GuideNotifier, Loaded<Guide>>(
      GuideNotifier.new,
      // Pas de nouvel essai automatique : 30 Mo par essai.
      retry: noRetry,
    );

class GuideNotifier extends AsyncNotifier<Loaded<Guide>> {
  @override
  Future<Loaded<Guide>> build() async {
    final channels = ref.watch(_guideChannelsProvider);
    if (channels == null) return const Loaded(Guide.empty);
    final repository = ref.watch(guideRepositoryProvider);
    return await _loadGuide(repository, channels.ids) ??
        const Loaded(Guide.empty);
  }

  /// « Actualiser » : retélécharge, même avec un cache récent. En cas
  /// d'échec, le guide affiché reste.
  Future<void> refresh() async {
    final channels = ref.read(_guideChannelsProvider);
    if (channels == null) return;
    final repository = ref.read(guideRepositoryProvider);
    final loaded = await _loadGuide(repository, channels.ids, refresh: true);
    if (loaded != null && ref.mounted) state = AsyncData(loaded);
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

/// Programmes d'une chaîne sur une plage (grille).
final guideRangeProvider = Provider.autoDispose
    .family<List<Programme>, ({String channel, DateTime from, DateTime to})>(
      (ref, range) =>
          ref
              .watch(guideProvider)
              .value
              ?.value
              .between(range.channel, range.from, range.to) ??
          const [],
    );
