import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/account_status_screen.dart';
import '../accounts/accounts_screen.dart';
import '../catalog/catalog_settings_screen.dart';
import 'settings.dart';

/// Roue des réglages, en haut à droite des onglets.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Réglages',
    icon: const Icon(Icons.settings),
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    ),
  );
}

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
          ListTile(
            leading: const Icon(Icons.filter_list),
            title: const Text('Catalogue'),
            subtitle: const Text('Pays affichés, contenu adulte, catégories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const CatalogSettingsScreen(),
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
