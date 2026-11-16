import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../logging.dart';
import '../server/json_read.dart';
import 'account.dart';
import 'account_files.dart';

/// Les comptes et le compte actif, valeur immuable.
final class AccountsState {
  const AccountsState({this.accounts = const [], this.activeId});

  static AccountsState fromJson(Object? json) {
    final map = asMap(json);
    final accounts = [
      for (final entry in asList(map['accounts'])) ?Account.fromJson(entry),
    ];
    return AccountsState(
      accounts: accounts,
      activeId: asId(map['active']),
    )._withValidActive();
  }

  final List<Account> accounts;
  final String? activeId;

  Account? get active => accounts.where((a) => a.id == activeId).firstOrNull;

  /// Ajoute [account], ou remplace celui qui a le même `id`.
  AccountsState withAccount(Account account, {bool activate = false}) {
    final exists = accounts.any((a) => a.id == account.id);
    return AccountsState(
      accounts: exists
          ? [for (final a in accounts) a.id == account.id ? account : a]
          : [...accounts, account],
      activeId: activate ? account.id : activeId,
    )._withValidActive();
  }

  /// Retire le compte [id]. Si c'était l'actif, le premier restant le devient.
  AccountsState without(String id) => AccountsState(
    accounts: [
      for (final a in accounts)
        if (a.id != id) a,
    ],
    activeId: activeId == id ? null : activeId,
  )._withValidActive();

  AccountsState withActive(String id) =>
      AccountsState(accounts: accounts, activeId: id)._withValidActive();

  // Un compte actif existe dès qu'il y a au moins un compte, et seulement alors.
  AccountsState _withValidActive() {
    if (accounts.isEmpty) {
      return activeId == null ? this : const AccountsState();
    }
    if (active != null) return this;
    return AccountsState(accounts: accounts, activeId: accounts.first.id);
  }

  Map<String, Object?> toJson() => {
    'active': activeId,
    'accounts': [for (final a in accounts) a.toJson()],
  };
}

/// Lecture et écriture des comptes dans le stockage chiffré du système.
///
/// Un seul enregistrement contient tous les comptes et le compte actif : une
/// écriture les change ensemble, sans état intermédiaire incohérent.
final class AccountStore {
  AccountStore._(
    this._storage,
    this._resetting,
    this._current, {
    this._unreadable = false,
  });

  static const _key = 'accounts';

  /// Copie d'un enregistrement déchiffré mais corrompu, gardée avant qu'une
  /// écriture le remplace. Elle reste dans le stockage chiffré, et part avec
  /// la suppression d'un compte ([forgetBackup]) : elle peut porter ses
  /// identifiants.
  static const _backupKey = 'accounts.bak';

  /// Sur erreur de déchiffrement, le plugin Android effaçait lui-même tout
  /// le stockage (`resetOnError` vaut `true` par défaut) : un échec passager
  /// du Keystore perdait les comptes. Les autres options gardent leurs
  /// valeurs par défaut : une 1.2.0 relit ses comptes.
  static const _android = AndroidOptions(resetOnError: false);

  final FlutterSecureStorage _storage;

  /// Le même stockage, qui repart de zéro si le plugin Android n'a pas pu
  /// s'initialiser (clé du Keystore perdue) : sinon aucun compte ne pourrait
  /// plus jamais être enregistré. Ailleurs, simple nouvelle tentative.
  final FlutterSecureStorage _resetting;

  AccountsState _current;

  /// Dernier état enregistré (ou lu à l'ouverture, avant le premier rendu).
  AccountsState get current => _current;

  bool _unreadable;

  /// Vrai si l'enregistrement existait mais n'a pas pu être lu : l'état sans
  /// compte ne dit alors rien des dossiers de données, qu'il faut garder.
  /// Faux dès qu'une relecture ou une écriture réussit.
  bool get unreadable => _unreadable;

  static Future<AccountStore> open([
    FlutterSecureStorage storage = const FlutterSecureStorage(
      aOptions: _android,
    ),
    FlutterSecureStorage resetting = const FlutterSecureStorage(),
  ]) async {
    try {
      final raw = await storage.read(key: _key);
      final state = raw == null
          ? const AccountsState()
          : AccountsState.fromJson(jsonDecode(raw));
      return AccountStore._(storage, resetting, state);
    } on Exception catch (e) {
      // JSON corrompu, ou déchiffrement impossible (Keystore passager,
      // profil copié sur une autre machine) : on repart sans compte plutôt
      // que de planter, et la première écriture relit d'abord ([recover]).
      // Le contenu n'est jamais loggé : il porte les mots de passe.
      log('Comptes illisibles, ignorés', error: e.runtimeType);
      return AccountStore._(
        storage,
        resetting,
        const AccountsState(),
        unreadable: true,
      );
    }
  }

  /// Avant une écriture, si l'enregistrement était illisible à l'ouverture :
  /// le relit, pour ne pas écraser des comptes qu'un échec passager cachait.
  /// Rend les comptes retrouvés, sur lesquels appliquer le changement ;
  /// `null` s'il n'y a rien à reprendre. Un enregistrement lu mais corrompu
  /// est copié sous [_backupKey].
  Future<AccountsState?> recover() async {
    if (!_unreadable) return null;
    final String? raw;
    try {
      raw = await _storage.read(key: _key);
    } on Exception catch (e) {
      log('Comptes toujours illisibles', error: e.runtimeType);
      return null;
    }
    if (raw == null) return null;
    try {
      final state = AccountsState.fromJson(jsonDecode(raw));
      _current = state;
      _unreadable = false;
      return state;
    } on FormatException {
      await _storage.write(key: _backupKey, value: raw);
      return null;
    }
  }

  Future<void> forgetBackup() => _storage.delete(key: _backupKey);

  Future<void> save(AccountsState state) async {
    final value = jsonEncode(state.toJson());
    try {
      await _storage.write(key: _key, value: value);
    } on Exception catch (e) {
      if (!_unreadable) rethrow;
      log('Comptes illisibles, stockage remis à zéro', error: e.runtimeType);
      await _resetting.write(key: _key, value: value);
    }
    _current = state;
    _unreadable = false;
  }
}

/// Au démarrage, range les dossiers de données d'après les comptes lus.
///
/// Sans aucun compte, rien n'est rangé : un stockage illisible peut aussi
/// revenir vide sans erreur (Android efface sa clé, Windows son fichier au
/// lancement suivant), et ses dossiers doivent rester. La suppression du
/// dernier compte efface déjà son dossier elle-même ([AccountsNotifier.remove]).
///
/// [videos] : les dossiers des vidéos téléchargées, rangés de même.
Future<void> syncAccountFolders(
  AccountStore accounts,
  AccountFiles files, [
  AccountFiles? videos,
]) async {
  final ids = {for (final a in accounts.current.accounts) a.id};
  if (accounts.unreadable || ids.isEmpty) return;
  await files.sync(ids);
  await videos?.sync(ids);
}

/// Ouvert dans `main()` avant le premier rendu, puis injecté via un override.
final accountStoreProvider = Provider<AccountStore>(
  (ref) => throw UnimplementedError('accountStoreProvider doit être surchargé'),
);

final accountsProvider = NotifierProvider<AccountsNotifier, AccountsState>(
  AccountsNotifier.new,
);

final class AccountsNotifier extends Notifier<AccountsState> {
  @override
  AccountsState build() => ref.watch(accountStoreProvider).current;

  /// Le dossier du compte est créé avant l'enregistrement : dès que le
  /// compte devient actif, le catalogue démarre et a besoin de son cache.
  Future<void> save(Account account, {bool activate = false}) async {
    await ref.read(accountFilesProvider).create(account.id);
    await _commit((s) => s.withAccount(account, activate: activate));
  }

  /// Efface les identifiants du compte, puis ses dossiers de données et de
  /// vidéos.
  Future<void> remove(String id) async {
    await _commit((s) => s.without(id));
    await ref.read(accountStoreProvider).forgetBackup();
    for (final files in [
      ref.read(accountFilesProvider),
      ?ref.read(downloadFilesProvider),
    ]) {
      try {
        await files.delete(id);
      } on FileSystemException catch (e) {
        // Fichier verrouillé par Windows : il restera des données locales,
        // mais le compte est bien supprimé. Le rangement du prochain
        // démarrage les effacera.
        log('Dossier du compte non effacé', error: e.osError?.errorCode);
      }
    }
  }

  Future<void> activate(String id) => _commit((s) => s.withActive(id));

  Future<void> _pending = Future.value();

  /// Les écritures passent l'une après l'autre, chacune partant de l'état
  /// laissé par la précédente : un clic pendant une suppression ne fait pas
  /// revenir le compte supprimé.
  ///
  /// Écrit d'abord : en cas d'échec, l'écran garde l'état réellement enregistré.
  Future<void> _commit(AccountsState Function(AccountsState) change) {
    final run = _pending.then((_) async {
      final store = ref.read(accountStoreProvider);
      if (await store.recover() case final found?) state = found;
      final next = change(state);
      await store.save(next);
      state = next;
    });
    // Un échec est remonté à l'appelant, sans bloquer les écritures suivantes.
    _pending = run.then<void>((_) {}, onError: (_) {});
    return run;
  }
}

final activeAccountProvider = Provider<Account?>(
  (ref) => ref.watch(accountsProvider.select((s) => s.active)),
);
