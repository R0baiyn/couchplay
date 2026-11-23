import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/app_settings.dart';
import '../focus_ring.dart';
import '../television.dart';
import 'journal_screen.dart';

/// D-069 : ce qui sert aux essais et au dépannage, hors de Réglages.
class AdvancedSettingsScreen extends ConsumerWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tv = ref.watch(televisionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages avancés')),
      body: ListView(
        children: [
          // Le premier interrupteur prend le focus, pour la télécommande.
          if (tv) const _DirectVideoTile(),
          _DebugTile(autofocus: !tv),
          ListTile(
            key: const ValueKey('settings.journal'),
            leading: const Icon(Icons.receipt_long_outlined),
            title: const FocusRing(child: Text('Journal')),
            subtitle: const Text('Pour comprendre un problème'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const JournalScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

/// D-068 : lecture directe sur TV, pour un appareil dont l'image saccade.
class _DirectVideoTile extends ConsumerWidget {
  const _DirectVideoTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      key: const ValueKey('settings.directVideo'),
      autofocus: true,
      secondary: const Icon(Icons.speed),
      title: const FocusRing(child: Text('Lecture directe')),
      subtitle: const Text("Si l'image saccade (après relance)"),
      value: ref.watch(appSettingsProvider.select((s) => s.directVideo)),
      onChanged: ref.read(appSettingsProvider.notifier).setDirectVideo,
    );
  }
}

/// Interrupteur du mode debug : infos techniques dans le lecteur.
class _DebugTile extends ConsumerWidget {
  const _DebugTile({required this.autofocus});

  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      key: const ValueKey('settings.debug'),
      autofocus: autofocus,
      secondary: const Icon(Icons.bug_report_outlined),
      title: const FocusRing(child: Text('Mode debug')),
      subtitle: const Text('Infos techniques dans le lecteur'),
      value: ref.watch(appSettingsProvider.select((s) => s.debug)),
      onChanged: ref.read(appSettingsProvider.notifier).setDebug,
    );
  }
}
