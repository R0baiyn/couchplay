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

  Account? get active {
    for (final account in accounts) {
      if (account.id == activeId) return account;
    }
    return null;
  }

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
  AccountStore._(this._storage, this._current);

  static const _key = 'accounts';

  final FlutterSecureStorage _storage;

  AccountsState _current;

  /// Dernier état enregistré (ou lu à l'ouverture, avant le premier rendu).
  AccountsState get current => _current;

  static Future<AccountStore> open([
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  ]) async {
    var state = const AccountsState();
    try {
      final raw = await storage.read(key: _key);
      if (raw != null) state = AccountsState.fromJson(jsonDecode(raw));
    } on Exception catch (e) {
      // JSON corrompu, ou déchiffrement impossible (profil copié sur une
      // autre machine) : on repart sans compte plutôt que de planter. La
      // prochaine écriture remplace l'enregistrement illisible.
      // Le contenu n'est jamais loggé : il porte les mots de passe.
      log('Comptes illisibles, ignorés', error: e.runtimeType);
    }
    return AccountStore._(storage, state);
  }

  Future<void> save(AccountsState state) async {
    await _storage.write(key: _key, value: jsonEncode(state.toJson()));
    _current = state;
  }
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

  Future<void> save(Account account, {bool activate = false}) async {
    await _commit((s) => s.withAccount(account, activate: activate));
    await ref.read(accountFilesProvider).create(account.id);
  }

  /// Efface les identifiants du compte, puis son dossier de données.
  Future<void> remove(String id) async {
    await _commit((s) => s.without(id));
    try {
      await ref.read(accountFilesProvider).delete(id);
    } on FileSystemException catch (e) {
      // Fichier verrouillé par Windows : il restera des données locales,
      // mais le compte est bien supprimé.
      log('Dossier du compte non effacé', error: e.osError?.errorCode);
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
      final next = change(state);
      await ref.read(accountStoreProvider).save(next);
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
