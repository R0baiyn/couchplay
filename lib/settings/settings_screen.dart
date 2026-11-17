import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/account_status_screen.dart';
import '../accounts/accounts_screen.dart';
import '../catalog/catalog_settings_screen.dart';
import '../focus_ring.dart';
import '../television.dart';
import '../update/update_dialog.dart';
import '../update/updater.dart';
import 'app_settings.dart';

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
              key: const ValueKey('settings.open'),
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
              key: const ValueKey('settings.open'),
              onTap: () => _open(context),
              customBorder: const StadiumBorder(),
              child: FocusRing(
                radius: 16,
                child: SizedBox(
                  width: 56,
                  height: 32,
                  child: Icon(Icons.settings_outlined, color: color),
                ),
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
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pas de téléchargements sur TV (D-034) : pas de réglages non plus.
    final tv = ref.watch(televisionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        children: [
          ListTile(
            key: const ValueKey('settings.accounts'),
            autofocus: true,
            leading: const Icon(Icons.manage_accounts),
            title: const FocusRing(child: Text('Comptes')),
            subtitle: const Text('Ajouter, modifier ou changer de compte'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
            ),
          ),
          ListTile(
            key: const ValueKey('settings.status'),
            leading: const Icon(Icons.verified_user_outlined),
            title: const FocusRing(child: Text('Abonnement')),
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
            key: const ValueKey('settings.catalog'),
            leading: const Icon(Icons.filter_list),
            title: const FocusRing(child: Text('Catalogue')),
            subtitle: const Text('Pays affichés, contenu adulte, catégories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const CatalogSettingsScreen(),
              ),
            ),
          ),
          if (!tv) ...const [_WifiOnlyTile(), _DeleteWatchedTile()],
          const _DebugTile(),
          const Divider(),
          const _VersionTile(),
        ],
      ),
    );
  }
}

/// D-037 : sur réseau mobile, la file des téléchargements attend le Wi-Fi.
class _WifiOnlyTile extends ConsumerWidget {
  const _WifiOnlyTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      key: const ValueKey('settings.wifiOnly'),
      secondary: const Icon(Icons.wifi),
      title: const FocusRing(child: Text('Télécharger en Wi-Fi seulement')),
      subtitle: const Text('Sur réseau mobile, les téléchargements attendent'),
      value: ref.watch(appSettingsProvider.select((s) => s.wifiOnly)),
      onChanged: ref.read(appSettingsProvider.notifier).setWifiOnly,
    );
  }
}

/// D-037 : la vidéo d'un contenu vu est supprimée à la sortie du lecteur.
class _DeleteWatchedTile extends ConsumerWidget {
  const _DeleteWatchedTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      key: const ValueKey('settings.deleteWatched'),
      secondary: const Icon(Icons.auto_delete_outlined),
      title: const FocusRing(child: Text('Effacer une fois vu')),
      subtitle: const Text('Supprime la vidéo téléchargée après la lecture'),
      value: ref.watch(appSettingsProvider.select((s) => s.deleteWatched)),
      onChanged: ref.read(appSettingsProvider.notifier).setDeleteWatched,
    );
  }
}

/// Interrupteur du mode debug : infos techniques dans le lecteur.
class _DebugTile extends ConsumerWidget {
  const _DebugTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      key: const ValueKey('settings.debug'),
      secondary: const Icon(Icons.bug_report_outlined),
      title: const FocusRing(child: Text('Mode debug')),
      subtitle: const Text('Infos techniques dans le lecteur'),
      value: ref.watch(appSettingsProvider.select((s) => s.debug)),
      onChanged: ref.read(appSettingsProvider.notifier).setDebug,
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
      key: const ValueKey('settings.version'),
      leading: const Icon(Icons.info_outline),
      title: FocusRing(child: Text('Version $version')),
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
