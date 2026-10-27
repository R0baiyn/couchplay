import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'accounts/account_store.dart';
import 'accounts/login_screen.dart';
import 'catalog/catalog_screen.dart';
import 'server/models.dart';
import 'settings/settings.dart';

class CouchPlayApp extends ConsumerWidget {
  const CouchPlayApp({super.key, required this.home});

  final Widget home;

  // Construits une seule fois : MaterialApp ne recalcule rien au changement de thème.
  static final _light = ThemeData(colorSchemeSeed: Colors.deepPurple);
  static final _dark = ThemeData(
    colorSchemeSeed: Colors.deepPurple,
    brightness: Brightness.dark,
  );

  static final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(
      themePreferenceProvider.select((theme) => theme.themeMode),
    );
    return MaterialApp(
      title: 'CouchPlay',
      debugShowCheckedModeBanner: false,
      theme: _light,
      darkTheme: _dark,
      themeMode: themeMode,
      navigatorKey: _navigator,
      // Échap revient en arrière partout, comme le bouton retour (clavier,
      // télécommande). Placé au-dessus du Navigator, ce raccourci reçoit la
      // touche en dernier : un menu ou un champ qui la gère passe avant.
      builder: (context, child) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _navigator.currentState?.maybePop(),
        },
        // Encoche, caméra et boutons du téléphone : rien ne passe dessous,
        // surtout en paysage où ils sont sur les côtés. Le haut est géré par
        // les barres d'application.
        child: SafeArea(top: false, child: child!),
      ),
      home: home,
    );
  }
}

/// Écran de départ : la connexion tant qu'aucun compte n'existe, sinon
/// l'accueil du compte actif.
class HomeGate extends ConsumerWidget {
  const HomeGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAccount = ref.watch(
      activeAccountProvider.select((a) => a != null),
    );
    return hasAccount ? const HomeShell() : const LoginScreen();
  }
}

/// Onglets Films et Séries (les réglages sont en haut à droite) : barre en bas sur écran étroit,
/// rail sur le côté sur grand écran (règle 9).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _tabs = [
    (Icons.movie_outlined, Icons.movie, 'Films'),
    (Icons.tv_outlined, Icons.tv, 'Séries'),
  ];

  var _index = 0;

  // Un onglet n'est construit qu'à sa première visite : pas de requête pour
  // les séries tant qu'on ne les ouvre pas. Ensuite, il garde son état.
  final _visited = {0};

  void _select(int index) => setState(() {
    _index = index;
    _visited.add(index);
  });

  Widget _tab(int index) => switch (index) {
    0 => const CatalogScreen(kind: ContentKind.movies),
    _ => const CatalogScreen(kind: ContentKind.series),
  };

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < _tabs.length; i++)
          _visited.contains(i) ? _tab(i) : const SizedBox.shrink(),
      ],
    );
    if (MediaQuery.sizeOf(context).width >= 720) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final (icon, selected, label) in _tabs)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(selected),
                    label: Text(label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          for (final (icon, selected, label) in _tabs)
            NavigationDestination(
              icon: Icon(icon),
              selectedIcon: Icon(selected),
              label: label,
            ),
        ],
      ),
    );
  }
}
