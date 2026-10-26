import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer « ${account.name} » ?'),
        content: const Text(
          'Ses identifiants et ses données sur cet appareil seront effacés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(accountsProvider.notifier).remove(account.id);
    // Plus aucun compte : retour à l'écran de connexion, à la racine.
    if (context.mounted && ref.read(accountsProvider).accounts.isEmpty) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Comptes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un compte'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          for (final account in state.accounts)
            ListTile(
              leading: Icon(
                account.id == state.activeId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(account.name),
              subtitle: Text(account.host),
              selected: account.id == state.activeId,
              onTap: () =>
                  ref.read(accountsProvider.notifier).activate(account.id),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Modifier',
                    icon: const Icon(Icons.edit),
                    onPressed: () => _edit(context, account),
                  ),
                  IconButton(
                    tooltip: 'Supprimer',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _remove(context, ref, account),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
