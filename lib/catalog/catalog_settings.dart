import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/account_files.dart';
import '../accounts/account_store.dart';
import '../logging.dart';
import '../server/json_read.dart';
import '../server/models.dart';
import 'category_filter.dart';

/// Filtre du catalogue du compte actif, gardé dans
/// `accounts/<id>/catalog_settings.json` : chaque fournisseur a ses propres
/// préfixes, donc chaque compte ses propres choix.
final catalogFilterProvider =
    NotifierProvider.autoDispose<CatalogFilterNotifier, CatalogFilter>(
      CatalogFilterNotifier.new,
    );

final class CatalogFilterNotifier extends Notifier<CatalogFilter> {
  File? _file;

  @override
  CatalogFilter build() {
    final id = ref.watch(activeAccountProvider.select((a) => a?.id));
    if (id == null) {
      _file = null;
      return const CatalogFilter();
    }
    final file = _file = File(
      '${ref.watch(accountFilesProvider).of(id).path}'
      '${Platform.pathSeparator}catalog_settings.json',
    );
    // Lecture synchrone : quelques centaines d'octets, et le filtre doit être
    // connu avant d'afficher la moindre catégorie.
    try {
      return _fromJson(jsonDecode(file.readAsStringSync()));
    } on FileSystemException {
      return const CatalogFilter();
    } on FormatException {
      return const CatalogFilter();
    }
  }

  Future<void> setTag(String tag, {required bool shown}) => _update(
    CatalogFilter(
      tags: shown ? {...state.tags, tag} : ({...state.tags}..remove(tag)),
      showAdult: state.showAdult,
      overrides: state.overrides,
    ),
  );

  Future<void> setShowAdult(bool shown) => _update(
    CatalogFilter(
      tags: state.tags,
      showAdult: shown,
      overrides: state.overrides,
    ),
  );

  /// Affiche ou masque une catégorie. Un choix égal à ce que donneraient les
  /// pays et l'adulte est retiré : la catégorie suit de nouveau la règle.
  Future<void> setCategory(
    ContentKind kind,
    Category category, {
    required bool shown,
  }) {
    final key = CatalogFilter.overrideKey(kind, category.id);
    final overrides = {...state.overrides}..remove(key);
    final byRule = CatalogFilter(
      tags: state.tags,
      showAdult: state.showAdult,
    ).isVisible(kind, category);
    if (shown != byRule) overrides[key] = shown;
    return _update(
      CatalogFilter(
        tags: state.tags,
        showAdult: state.showAdult,
        overrides: overrides,
      ),
    );
  }

  Future<void> resetCategories() =>
      _update(CatalogFilter(tags: state.tags, showAdult: state.showAdult));

  Future<void> _pending = Future.value();

  // Appliqué tout de suite ; l'écriture suit, atomique (fichier temporaire
  // renommé) et en série : deux clics rapides n'écrivent pas le même fichier
  // temporaire en même temps. Un échec garde le choix pour la session.
  Future<void> _update(CatalogFilter next) {
    state = next;
    final file = _file;
    if (file == null) return Future.value();
    return _pending = _pending.then((_) async {
      final temp = File('${file.path}.tmp');
      try {
        await file.parent.create(recursive: true);
        await temp.writeAsString(jsonEncode(_toJson(next)), flush: true);
        await temp.rename(file.path);
      } on FileSystemException catch (e) {
        log('Réglages du catalogue non écrits', error: e.osError?.errorCode);
      }
    });
  }

  static CatalogFilter _fromJson(Object? json) {
    final map = asMap(json);
    return CatalogFilter(
      tags: {for (final tag in asList(map['tags'])) ?asString(tag)},
      showAdult: asBool(map['showAdult']) ?? false,
      overrides: {
        for (final MapEntry(:key, :value) in asMap(map['overrides']).entries)
          key: ?asBool(value),
      },
    );
  }

  static Map<String, Object?> _toJson(CatalogFilter filter) => {
    'tags': filter.tags.toList()..sort(),
    'showAdult': filter.showAdult,
    'overrides': filter.overrides,
  };
}
