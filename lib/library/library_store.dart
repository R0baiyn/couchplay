import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/account_files.dart';
import '../accounts/account_store.dart';
import '../logging.dart';
import 'library.dart';

/// Lecture et écriture de `accounts/<id>/library.json`. Seul point d'écriture
/// des favoris et de la progression : la future synchronisation passera ici.
final class LibraryStore {
  LibraryStore(this.file);

  final File file;

  /// Lit la bibliothèque. Un fichier absent ou vide donne une bibliothèque
  /// vide ; un fichier corrompu est mis de côté en `library.json.bak`, pour
  /// ne pas perdre de trace, et l'app repart de zéro.
  Library load() {
    // Lecture synchrone : quelques dizaines de Ko, nécessaires avant
    // d'afficher l'accueil.
    for (var attempt = 1; ; attempt++) {
      try {
        final text = file.readAsStringSync();
        if (text.trim().isEmpty) return const Library();
        return Library.fromJson(jsonDecode(text));
      } on PathNotFoundException {
        return const Library();
      } on FileSystemException catch (e) {
        // Texte mal encodé, entre autres : pas un verrou.
        if (!_locked.contains(e.osError?.errorCode)) return _setAside();
        // Verrou : sous Windows, une écriture de l'app (renommage du fichier
        // temporaire) ou un antivirus bloque la lecture quelques
        // millisecondes. Le fichier n'est pas illisible : on réessaie, puis
        // on le laisse en place sans plus rien écrire jusqu'au prochain
        // lancement.
        if (attempt < 5) {
          sleep(const Duration(milliseconds: 20));
          continue;
        }
        _readOnly = true;
        log('Bibliothèque verrouillée, lue vide', error: e.osError?.errorCode);
        return const Library();
      } on Exception {
        return _setAside();
      }
    }
  }

  /// Erreurs Windows d'un fichier ouvert ailleurs : partage refusé (32),
  /// plage verrouillée (33).
  static const _locked = {32, 33};

  /// JSON invalide ou texte mal encodé : jamais écrasé sans trace par la
  /// prochaine écriture.
  Library _setAside() {
    log('Bibliothèque illisible, mise de côté en library.json.bak');
    try {
      file.renameSync('${file.path}.bak');
    } on FileSystemException catch (e) {
      // Fichier verrouillé (antivirus, synchronisation) : on n'écrit plus
      // rien jusqu'au prochain lancement, plutôt que de l'écraser.
      _readOnly = true;
      log('Bibliothèque non mise de côté', error: e.osError?.errorCode);
    }
    return const Library();
  }

  Future<void>? _pending;
  var _readOnly = false;

  /// Écrit [library] de façon atomique (fichier temporaire renommé), une
  /// écriture après l'autre. Un échec est loggé : l'état reste en mémoire.
  Future<void> save(Library library) {
    if (_readOnly) return Future.value();
    final text = const JsonEncoder.withIndent(' ').convert(library.toJson());
    return _pending = (_pending ?? Future.value()).then((_) async {
      final temp = File('${file.path}.tmp');
      try {
        await temp.writeAsString(text, flush: true);
        await temp.rename(file.path);
      } on FileSystemException catch (e) {
        log('Bibliothèque non écrite', error: e.osError?.errorCode);
      }
    });
  }
}

/// Bibliothèque du compte actif, rechargée au changement de compte.
final libraryProvider = NotifierProvider<LibraryNotifier, Library>(
  LibraryNotifier.new,
);

final class LibraryNotifier extends Notifier<Library> {
  LibraryStore? _store;

  @override
  Library build() {
    final id = ref.watch(activeAccountProvider.select((a) => a?.id));
    if (id == null) {
      _store = null;
      return const Library();
    }
    final folder = ref.watch(accountFilesProvider).of(id).path;
    final store = _store = LibraryStore(
      File('$folder${Platform.pathSeparator}library.json'),
    );
    return store.load();
  }

  bool isFavorite(String key) => state.favorites.containsKey(key);

  Future<void> toggleFavorite({
    required String key,
    required String name,
    String? poster,
  }) => _set(
    isFavorite(key)
        ? state.withoutFavorite(key)
        : state.withFavorite(
            Favorite(
              key: key,
              name: name,
              poster: poster,
              addedAt: DateTime.now().toUtc(),
            ),
          ),
  );

  Future<void> removeFavorites(Iterable<String> keys) =>
      _set(keys.fold(state, (library, key) => library.withoutFavorite(key)));

  /// Enregistre où on en est. Un contenu déjà vu le reste, même si on
  /// revient en arrière ; il ne redevient « non vu » qu'à la main.
  Future<void> saveProgress(
    PlayItem item, {
    required Duration position,
    required Duration duration,
  }) {
    final previous = state.progress[item.key];
    final known = duration > Duration.zero
        ? duration
        : (previous?.duration ?? Duration.zero);
    return _set(
      state.withProgress(
        Progress(
          item: item,
          position: position,
          duration: known,
          watched:
              (previous?.watched ?? false) ||
              Progress.reachesEnd(position, known),
          // Regarder de nouveau un contenu retiré le fait revenir.
          hidden: false,
          updatedAt: DateTime.now().toUtc(),
        ),
      ),
    );
  }

  /// « Marquer comme vu / non vu », depuis la liste des épisodes.
  Future<void> setWatched(PlayItem item, {required bool watched}) {
    final previous = state.progress[item.key];
    return _set(
      state.withProgress(
        Progress(
          item: item,
          // Vu : à la fin, s'il y en a une ; non vu : on repart du début.
          position: watched
              ? (previous != null && previous.duration > Duration.zero
                    ? previous.duration
                    : (previous?.position ?? Duration.zero))
              : Duration.zero,
          duration: previous?.duration ?? Duration.zero,
          watched: watched,
          updatedAt: DateTime.now().toUtc(),
        ),
      ),
    );
  }

  /// Retire de « Continuer à regarder » sans toucher à la progression. Pour
  /// une série, tous ses épisodes commencés sont retirés, sinon un épisode
  /// plus ancien prendrait aussitôt la place.
  Future<void> hide(Progress entry) {
    var library = state;
    for (final other in state.progress.values) {
      final sameSeries =
          entry.item.seriesId != null &&
          other.item.seriesId == entry.item.seriesId;
      if (other.item.key == entry.item.key || sameSeries) {
        library = library.withProgress(other.copyWith(hidden: true));
      }
    }
    return _set(library);
  }

  Future<void> _set(Library next) {
    state = next;
    return _store?.save(next) ?? Future.value();
  }
}
