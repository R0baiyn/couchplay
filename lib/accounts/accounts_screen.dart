import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../confirm.dart';
import '../focus_ring.dart';
import 'account.dart';
import 'account_store.dart';
import 'login_screen.dart';

/// Liste des comptes : choisir l'actif, ajouter, modifier, supprimer.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  Future<void> _edit(BuildContext context, [Account? account]) =>
      Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => LoginScreen(account: account)),
      );

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    Account account,
  ) async {
    final confirmed = await confirm(
      context,
      title: 'Supprimer « ${account.name} » ?',
      content:
          'Ses identifiants et ses données sur cet appareil seront effacés.',
      action: 'Supprimer',
    );
    if (!confirmed || !context.mounted) return;
    if (!await _write(
      context,
      ref.read(accountsProvider.notifier).remove(account.id),
    )) {
      return;
    }
    // Plus aucun compte : retour à l'écran de connexion, à la racine.
    if (context.mounted && ref.read(accountsProvider).accounts.isEmpty) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  /// Attend [write] ; en cas d'échec du stockage, le dit au lieu de se taire.
  static Future<bool> _write(BuildContext context, Future<void> write) async {
    try {
      await write;
      return true;
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d\'enregistrer le changement'),
          ),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Comptes')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('accounts.add'),
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un compte'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          for (final account in state.accounts)
            // Boutons à côté de la ligne, pas dedans : → depuis le compte les
            // atteint (télécommande, clavier). Dans la ligne, ils n'étaient
            // ni à sa droite ni dessous pour les flèches.
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    key: ValueKey('accounts.row.${account.id}'),
                    leading: Icon(
                      account.id == state.activeId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: FocusRing(child: Text(account.name)),
                    subtitle: Text(account.host),
                    selected: account.id == state.activeId,
                    onTap: () => _write(
                      context,
                      ref.read(accountsProvider.notifier).activate(account.id),
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('accounts.edit.${account.id}'),
                  tooltip: 'Modifier',
                  icon: const Icon(Icons.edit),
                  onPressed: () => _edit(context, account),
                ),
                IconButton(
                  key: ValueKey('accounts.delete.${account.id}'),
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _remove(context, ref, account),
                ),
                const SizedBox(width: 8),
              ],
            ),
        ],
      ),
    );
  }
}
