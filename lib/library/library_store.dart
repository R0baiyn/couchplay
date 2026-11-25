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
    // Écriture encore en file : le fichier n'est pas à jour.
    if (_unwritten[file.path] case final pending?) return pending;
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
        // Sans erreur système : texte mal encodé, le fichier est illisible.
        final code = e.osError?.errorCode;
        if (code == null) return _setAside();
        // Verrou : sous Windows, une écriture de l'app (renommage du fichier
        // temporaire) ou un antivirus bloque la lecture quelques
        // millisecondes. On réessaie.
        if (_locked.contains(code) && attempt < 5) {
          sleep(const Duration(milliseconds: 20));
          continue;
        }
        // Verrou qui dure, accès refusé passager… : le fichier n'est pas
        // illisible. On le laisse en place sans plus rien écrire jusqu'au
        // prochain lancement.
        _readOnly = true;
        log('Bibliothèque non lue, lue vide', error: code);
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

  /// Une seule file par fichier : le magasin est recréé à chaque changement
  /// de compte, et deux files pourraient écrire le même fichier dans le
  /// désordre (compte A, puis B, puis A).
  static final _writers = <String, SerialFileWriter>{};

  /// Par fichier, dernière bibliothèque confiée à la file et pas encore
  /// écrite : [load] la rend à la place du fichier.
  static final _unwritten = <String, Library>{};

  var _readOnly = false;

  /// Écrit [library] (voir [SerialFileWriter]).
  Future<void> save(Library library) {
    if (_readOnly) return Future.value();
    final path = file.path;
    _unwritten[path] = library;
    final writer = _writers.putIfAbsent(
      path,
      () => SerialFileWriter(failure: 'Bibliothèque non écrite'),
    );
    return writer
        .write(
          file,
          const JsonEncoder.withIndent(' ').convert(library.toJson()),
        )
        .whenComplete(() {
          if (identical(_unwritten[path], library)) _unwritten.remove(path);
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
    final store = _store = LibraryStore(
      File(ref.watch(accountFilesProvider).path(id, 'library.json')),
    );
    return store.load();
  }

  Future<void> addFavorite({
    required String key,
    required String name,
    String? poster,
  }) => _set(
    state.withFavorite(
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

  /// « Marquer comme vu / non vu », depuis la liste des épisodes. Ce n'est
  /// pas regarder : la date et le retrait de « Continuer à regarder » restent
  /// ceux de l'entrée, ou de sa série pour un épisode encore jamais marqué.
  Future<void> setWatched(PlayItem item, {required bool watched}) {
    final previous = state.progress[item.key];
    final seriesHidden =
        item.seriesId != null &&
        state.progress.values.any(
          (p) => p.hidden && p.item.seriesId == item.seriesId,
        );
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
          hidden: previous?.hidden ?? seriesHidden,
          updatedAt: previous?.updatedAt ?? DateTime.now().toUtc(),
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

  /// Efface la progression d'une ligne de l'historique : reprise et marque
  /// « vu » comprises.
  Future<void> removeProgress(String key) => _set(state.withoutProgress(key));

  Future<void> addChannelFavorite({
    required String id,
    required String name,
    int? number,
    String? logo,
  }) => _set(state.withChannelFavorite(_saved(id, name, number, logo)));

  Future<void> removeChannelFavorite(String id) =>
      _set(state.withoutChannelFavorite(id));

  /// Une chaîne a vraiment démarré : en tête des chaînes récentes.
  Future<void> addRecentChannel({
    required String id,
    required String name,
    int? number,
    String? logo,
  }) => _set(state.withRecentChannel(_saved(id, name, number, logo)));

  /// « Retirer » de la rangée « Chaînes récentes ».
  Future<void> removeRecentChannel(String id) =>
      _set(state.withoutRecentChannel(id));

  static SavedChannel _saved(
    String id,
    String name,
    int? number,
    String? logo,
  ) => SavedChannel(
    id: id,
    name: name,
    number: number,
    logo: logo,
    at: DateTime.now().toUtc(),
  );

  /// « Effacer l'historique » : la progression entière et les chaînes
  /// récentes ; les favoris et les chaînes favorites restent.
  Future<void> clearHistory() => _set(state.withoutHistory());

  Future<void> _set(Library next) {
    state = next;
    return _store?.save(next) ?? Future.value();
  }
}
