import '../library/library.dart';
import '../server/models.dart';

/// Une affiche du catalogue : un film et ses versions (4K, FHD, HD…), ou une
/// série.
final class CatalogEntry {
  const CatalogEntry(this.versions);

  /// La meilleure en premier ([compareVersions]) ; jamais vide.
  final List<CatalogItem> versions;

  CatalogItem get item => versions.first;
  ContentKind get kind => item.kind;

  /// Titre sans étiquettes : « Libre (2024) » pour toutes ses versions.
  String get title => item.parsedName.display;

  /// Affiche de la meilleure version qui en a une.
  String? get poster {
    for (final version in versions) {
      if (version.poster case final poster?) return poster;
    }
    return null;
  }
}

/// Affiches d'une liste, dans l'ordre du serveur : les versions d'un même
/// film n'en font qu'une, placée à la première d'entre elles.
///
/// Même film : même `tmdb_id`, sinon même titre et même année (deux
/// homonymes d'années différentes restent séparés ; sans année ni
/// `tmdb_id`, pas de regroupement : deux « Hamlet » ne sont pas forcément
/// le même). À n'appeler que sur des entrées de catégories visibles : sinon
/// un film français se regroupe avec sa version espagnole. Les séries ne
/// sont pas regroupées.
List<CatalogEntry> entriesOf(Iterable<CatalogItem> items) {
  final groups = <String, List<CatalogItem>>{};
  for (final item in items) {
    groups.putIfAbsent(_groupKey(item), () => []).add(item);
  }
  return [
    for (final versions in groups.values)
      CatalogEntry(
        versions.length == 1 ? versions : (versions..sort(compareVersions)),
      ),
  ];
}

String _groupKey(CatalogItem item) {
  if (item.kind == ContentKind.series) return 'i${item.id}';
  if (item.tmdbId case final tmdb?) return 't$tmdb';
  final name = item.parsedName;
  if (name.text.isEmpty || name.year == null) return 'i${item.id}';
  return 'n${name.text}|${name.year}';
}

/// Meilleure version d'abord : audio français avant version originale, puis
/// 4K, FHD, HD, sans étiquette, SD. À égalité, l'id du serveur, pour un
/// ordre stable d'une fois sur l'autre.
int compareVersions(CatalogItem a, CatalogItem b) {
  final x = a.parsedName;
  final y = b.parsedName;
  if (x.frenchAudio != y.frenchAudio) return x.frenchAudio ? -1 : 1;
  if (x.qualityRank != y.qualityRank) return y.qualityRank - x.qualityRank;
  final ids = (int.tryParse(a.id), int.tryParse(b.id));
  if (ids case (final i?, final j?)) return i.compareTo(j);
  return a.id.compareTo(b.id);
}

/// Nom des boutons de version, dans l'ordre de [versions] : l'étiquette du
/// nom (« 4K MULTI »), numérotée si deux versions ont la même, sinon
/// « Version 2 » d'après sa place.
List<String> versionLabels(List<CatalogItem> versions) {
  final seen = <String, int>{};
  return [
    for (final (index, version) in versions.indexed)
      switch (version.parsedName.label) {
        null => 'Version ${index + 1}',
        final label => switch (seen[label] = (seen[label] ?? 0) + 1) {
          1 => label,
          final count => '$label ($count)',
        },
      },
  ];
}

/// Version à proposer en ouvrant la fiche : la dernière regardée, sinon
/// celle mise en favori, sinon la meilleure.
CatalogItem preferredVersion(List<CatalogItem> versions, Library library) {
  CatalogItem? watched;
  DateTime? watchedAt;
  for (final version in versions) {
    final progress = library.progress['movie:${version.id}'];
    if (progress != null &&
        (watchedAt == null || progress.updatedAt.isAfter(watchedAt))) {
      watched = version;
      watchedAt = progress.updatedAt;
    }
  }
  return watched ??
      versions
          .where((v) => library.favorites.containsKey('movie:${v.id}'))
          .firstOrNull ??
      versions.first;
}
