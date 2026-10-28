import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'accounts/account_store.dart';
import 'accounts/login_screen.dart';
import 'catalog/catalog_screen.dart';
import 'library/home_screen.dart';
import 'search/search_index.dart';
import 'search/search_screen.dart';
import 'server/models.dart';
import 'settings/settings.dart';
import 'settings/settings_screen.dart';
import 'update/update_dialog.dart';
import 'update/updater.dart';

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

/// Onglets Accueil, Films, Séries et Recherche (les réglages sont en haut à
/// droite) : barre en bas sur écran étroit, rail sur le côté sur grand écran
/// (règle 9).
///
/// Une fois l'accueil affiché, l'index des films et celui des séries (d'où
/// viennent les grilles, la recherche et les versions) se chargent en
/// arrière-plan et restent chargés tant que cet écran existe. Ctrl+F ou /
/// ouvre la recherche, le curseur dans son champ.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _tabs = [
    (Icons.home_outlined, Icons.home, 'Accueil'),
    (Icons.movie_outlined, Icons.movie, 'Films'),
    (Icons.tv_outlined, Icons.tv, 'Séries'),
    (Icons.search_outlined, Icons.search, 'Recherche'),
  ];
  static const _searchTab = 3;

  var _index = 0;

  // Un onglet n'est construit qu'à sa première visite : pas de requête pour
  // les films ni les séries tant qu'on ne les ouvre pas. Ensuite, il garde son état.
  final _visited = {0};

  /// Pour Ctrl+F : le champ de la recherche.
  final _searchField = FocusNode();

  final _indexes = <ProviderSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    // Au niveau du clavier, pas d'un Focus : la touche marche aussi quand
    // rien n'a encore le focus (au lancement).
    HardwareKeyboard.instance.addHandler(_onKey);
    // Après la première image : l'accueil s'affiche avant que le gros
    // chargement commence.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final kind in ContentKind.values) {
        _indexes.add(ref.listenManual(catalogIndexProvider(kind), (_, _) {}));
      }
    });
    // Déjà connue si l'accueil est recréé (reconnexion) : lue directement,
    // pas de setState pendant initState.
    _update = ref.read(startupUpdateProvider).value;
    ref.listenManual(startupUpdateProvider, (_, next) {
      if (next.value case final update?) setState(() => _update = update);
    });
  }

  /// Mise à jour trouvée au démarrage, pas encore proposée : elle attend que
  /// l'accueil soit devant, jamais par-dessus le lecteur ou une fiche.
  Update? _update;

  void _offerUpdate() {
    final update = _update;
    final updater = ref.read(updaterProvider);
    if (update == null || updater == null) return;
    _update = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showUpdateDialog(context, updater, update);
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    for (final index in _indexes) {
      index.close();
    }
    _searchField.dispose();
    super.dispose();
  }

  void _select(int index) {
    setState(() {
      _index = index;
      _visited.add(index);
    });
    // La recherche s'ouvre prête à taper. Après la reconstruction : un
    // onglet tout juste créé n'a pas encore attaché son champ.
    if (index == _searchTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchField.requestFocus();
      });
    }
  }

  /// `true` : touche prise ; sur ordinateur, son caractère (« / ») n'est
  /// alors pas tapé.
  bool _onKey(KeyEvent event) {
    // Seulement quand l'accueil est devant : pas sous le lecteur, une fiche,
    // un dialogue ou le panneau des catégories.
    if (event is! KeyDownEvent ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    final ctrlF =
        event.logicalKey == LogicalKeyboardKey.keyF &&
        HardwareKeyboard.instance.isControlPressed;
    // « / » s'écrit normalement dans un champ de texte.
    final slash =
        event.character == '/' &&
        FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<EditableText>() ==
            null;
    if (!ctrlF && !slash) return false;
    _select(_searchTab);
    return true;
  }

  // Créés une fois : changer d'onglet, ou ouvrir et fermer une fiche (la
  // route de l'accueil change d'état), ne reconstruit pas les onglets.
  final _built = <int, Widget>{};

  Widget _tab(int index) => switch (index) {
    0 => const HomeScreen(),
    1 => const CatalogScreen(kind: ContentKind.movies),
    2 => const CatalogScreen(kind: ContentKind.series),

    _ => SearchScreen(focusNode: _searchField),
  };

  @override
  Widget build(BuildContext context) {
    // Dépendance à la route : reconstruit quand l'accueil revient devant.
    if (ModalRoute.of(context)?.isCurrent ?? false) _offerUpdate();
    final body = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < _tabs.length; i++)
          _visited.contains(i)
              ? _built.putIfAbsent(i, () => _tab(i))
              : const SizedBox.shrink(),
      ],
    );
    if (MediaQuery.sizeOf(context).width >= railMinWidth) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              // Les réglages, tout en bas du rail.
              trailingAtBottom: true,
              trailing: const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: SettingsButton(inRail: true),
              ),

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
