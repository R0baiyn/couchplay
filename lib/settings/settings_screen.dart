import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/account_status_screen.dart';
import '../accounts/accounts_screen.dart';
import 'settings.dart';

/// Réglages de l'app.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _themeLabels = {
    ThemePreference.system: 'Comme le système',
    ThemePreference.light: 'Clair',
    ThemePreference.dark: 'Sombre',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themePreferenceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        children: [
          ListTile(
            autofocus: true,
            leading: const Icon(Icons.manage_accounts),
            title: const Text('Comptes'),
            subtitle: const Text('Ajouter, modifier ou changer de compte'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Abonnement'),
            subtitle: const Text('Statut, expiration, connexions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const AccountStatusScreen(),
              ),
            ),
          ),
          const Divider(),
          const ListTile(title: Text('Thème')),
          RadioGroup<ThemePreference>(
            groupValue: theme,
            onChanged: (value) {
              if (value != null) {
                ref.read(themePreferenceProvider.notifier).set(value);
              }
            },
            child: Column(
              children: [
                for (final value in ThemePreference.values)
                  RadioListTile<ThemePreference>(
                    value: value,
                    title: Text(_themeLabels[value]!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
