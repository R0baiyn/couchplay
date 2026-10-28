import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/account_status_screen.dart';
import '../accounts/accounts_screen.dart';
import '../catalog/catalog_settings_screen.dart';
import '../update/update_dialog.dart';
import '../update/updater.dart';

/// Largeur à partir de laquelle l'accueil a un rail sur le côté, et les
/// réglages en bas de ce rail plutôt que dans l'en-tête de chaque onglet :
/// 600 dp, le seuil de Material, qu'une tablette de 8″ en portrait dépasse.
const railMinWidth = 600.0;

/// Roue des réglages : en haut à droite des onglets, ou en bas du rail, avec
/// son libellé comme les onglets.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, this.inRail = false});

  /// Bouton du rail ; sinon, celui de l'en-tête, caché quand le rail est là.
  final bool inRail;

  void _open(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
  );

  @override
  Widget build(BuildContext context) {
    if (!inRail) {
      return MediaQuery.sizeOf(context).width >= railMinWidth
          ? const SizedBox.shrink()
          : IconButton(
              tooltip: 'Réglages',
              icon: const Icon(Icons.settings),
              onPressed: () => _open(context),
            );
    }
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    // Même allure qu'une destination du rail : le focus et le survol ne
    // surlignent que l'icône, dans sa pastille ; le libellé dessous se
    // touche aussi.
    return GestureDetector(
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            InkWell(
              onTap: () => _open(context),
              customBorder: const StadiumBorder(),
              child: SizedBox(
                width: 56,
                height: 32,
                child: Icon(Icons.settings_outlined, color: color),
              ),
            ),
            Text(
              'Réglages',
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Réglages de l'app.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          const _VersionTile(),
        ],
      ),
    );
  }
}

/// Version de l'app et, dans une version publiée, recherche d'une mise à jour.
class _VersionTile extends ConsumerStatefulWidget {
  const _VersionTile();

  @override
  ConsumerState<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends ConsumerState<_VersionTile> {
  var _checking = false;

  Future<void> _check(Updater updater) async {
    setState(() => _checking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final update = await updater.check();
      if (!mounted) return;
      if (update == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('CouchPlay est à jour.')),
        );
      } else {
        await showUpdateDialog(context, updater, update);
      }
    } on Exception {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Impossible de vérifier les mises à jour.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = ref.watch(appVersionProvider);
    final updater = ref.watch(updaterProvider);
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text('Version $version'),
      subtitle: updater == null
          ? null
          : const Text('Rechercher des mises à jour'),
      trailing: _checking
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: updater == null || _checking ? null : () => _check(updater),
    );
  }
}
