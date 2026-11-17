import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'catalog/catalog_index.dart';
import 'catalog/catalog_screen.dart';
import 'downloads/downloads_screen.dart';
import 'focus_ring.dart';
import 'library/home_screen.dart';
import 'search/search_screen.dart';
import 'server/models.dart';
import 'settings/settings_screen.dart';
import 'television.dart';
import 'update/update_dialog.dart';
import 'update/updater.dart';

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
  /// L'icône d'un onglet, à la taille de sa pastille ([width] × 32) : comme
  /// le bouton Réglages du rail, l'anneau entoure la pastille, pas le libellé.
  static Widget _tabIcon(IconData icon, double width, [Key? key]) => FocusRing(
    key: key,
    hug: true,
    radius: 16,
    child: SizedBox(width: width, height: 32, child: Icon(icon)),
  );

  static const _tabs = [
    (Icons.home_outlined, Icons.home, 'Accueil', ValueKey('shell.tabHome')),
    (Icons.movie_outlined, Icons.movie, 'Films', ValueKey('shell.tabMovies')),
    (Icons.tv_outlined, Icons.tv, 'Séries', ValueKey('shell.tabSeries')),
    (
      Icons.search_outlined,
      Icons.search,
      'Recherche',
      ValueKey('shell.tabSearch'),
    ),
    (
      Icons.download_outlined,
      Icons.download,
      'Hors ligne',
      ValueKey('shell.tabDownloads'),
    ),
  ];
  static const _searchTab = 3;

  /// Pas d'onglet « Hors ligne » sur TV (D-034) : le dernier est retiré.
  List<(IconData, IconData, String, Key)> get _shown =>
      ref.read(televisionProvider) ? _tabs.sublist(0, _tabs.length - 1) : _tabs;

  var _index = 0;

  // Un onglet n'est construit qu'à sa première visite : pas de requête pour
  // les films ni les séries tant qu'on ne les ouvre pas. Ensuite, il garde son état.
  final _visited = {0};

  /// Pour Ctrl+F : le champ de la recherche.
  final _searchField = FocusNode();

  /// Sur TV, le rail et l'onglet sont deux zones : ← au bord gauche de
  /// l'onglet revient à l'onglet choisi du rail, → depuis le rail revient au
  /// dernier élément visité de l'onglet, et les bouts du rail le gardent.
  /// Sans elles, les flèches visent l'élément le plus proche à l'écran (le
  /// bouton des réglages, une affiche coupée en haut).
  final _rail = FocusScopeNode(debugLabel: 'rail');
  final _content = FocusScopeNode(debugLabel: 'onglet');

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
      // Écoutes fermées par Riverpod au démontage de l'état.
      _indexes = [
        for (final kind in ContentKind.values)
          ref.listenManual(catalogIndexProvider(kind), (_, _) {}),
      ];
      _pauseIndexes(!(ModalRoute.of(context)?.isCurrent ?? false));
      // Sur TV, on voit tout de suite où est le focus : sur l'onglet choisi.
      if (ref.read(televisionProvider)) _focusTab();
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
    _exitArmed?.cancel();
    _searchField.dispose();
    _rail.dispose();
    _content.dispose();
    super.dispose();
  }

  /// Les éléments que les flèches atteignent dans [scope], de haut en bas
  /// puis de gauche à droite.
  static List<FocusNode> _reachable(FocusScopeNode scope) =>
      scope.traversalDescendants.where((node) => node.canRequestFocus).toList()
        ..sort((a, b) {
          final top = a.rect.top.compareTo(b.rect.top);
          return top != 0 ? top : a.rect.left.compareTo(b.rect.left);
        });

  KeyEventResult _railKey(FocusNode _, KeyEvent event) {
    if (arrowDirection(event) != TraversalDirection.right) {
      return KeyEventResult.ignored;
    }
    final last = _content.focusedChild;
    if (last != null && last.canRequestFocus) {
      last.requestFocus();
    } else {
      // Première visite : le contenu (une affiche) plutôt que les boutons
      // de l'en-tête (« Actualiser », en haut à droite).
      final reachable = _reachable(_content);
      bool inHeader(FocusNode node) =>
          node.context?.findAncestorWidgetOfExactType<AppBar>() != null;
      (reachable.where((node) => !inHeader(node)).firstOrNull ??
              reachable.firstOrNull)
          ?.requestFocus();
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _contentKey(FocusNode _, KeyEvent event) {
    final direction = arrowDirection(event);
    if (direction == null) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus;
    // La zone elle-même a le focus : l'élément qui l'avait a disparu (liste
    // vidée, tuile retirée). Une flèche le redonne au premier élément de
    // l'onglet, ou au rail s'il n'y en a aucun : sinon la télécommande ne
    // répondrait plus.
    if (focused is FocusScopeNode) {
      final first = _reachable(_content).firstOrNull;
      if (first != null) {
        first.requestFocus();
      } else {
        _focusTab();
      }
      return KeyEventResult.handled;
    }
    if (direction != TraversalDirection.left) return KeyEventResult.ignored;
    if (focused == null || !focused.focusInDirection(TraversalDirection.left)) {
      _focusTab();
    }
    return KeyEventResult.handled;
  }

  /// L'onglet choisi, dans le rail.
  void _focusTab() {
    // Les onglets d'abord, de haut en bas, puis les réglages.
    final tabs = _reachable(_rail);
    if (_index < tabs.length) tabs[_index].requestFocus();
  }

  /// Sur TV, le lecteur se ferme parfois seul (fin du dernier épisode,
  /// veille) ou au premier de deux appuis rapprochés : le retour suivant
  /// tomberait sur l'Accueil et quitterait l'app. Il faut donc un 2e appui
  /// dans les 2 s ; tant que ce minuteur court, le retour quitte.
  Timer? _exitArmed;
  static const _exitWindow = Duration(seconds: 2);

  void _armExit() {
    setState(
      () => _exitArmed = Timer(_exitWindow, () {
        if (mounted) setState(() => _exitArmed = null);
      }),
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Appuie encore sur retour pour quitter'),
          duration: _exitWindow,
        ),
      );
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

  /// Écoutes qui gardent les index chargés.
  var _indexes = const <ProviderSubscription<Object?>>[];
  var _indexesPaused = false;

  /// En pause quand l'accueil est caché (réglages du catalogue, lecteur) :
  /// les écrans de l'accueil le sont aussi (Riverpod les met en pause), donc
  /// plus personne n'attend l'index. Cinq catégories cochées dans les
  /// réglages le refont alors une fois au retour, pas cinq fois. Une fiche
  /// ouverte surveille l'index elle-même : il reste à jour pour elle.
  void _pauseIndexes(bool pause) {
    if (pause == _indexesPaused) return;
    _indexesPaused = pause;
    for (final subscription in _indexes) {
      pause ? subscription.pause() : subscription.resume();
    }
  }

  // Créés une fois : changer d'onglet, ou ouvrir et fermer une fiche (la
  // route de l'accueil change d'état), ne reconstruit pas les onglets.
  final _built = <int, Widget>{};

  Widget _tab(int index) => switch (index) {
    0 => const HomeScreen(),
    1 => const CatalogScreen(kind: ContentKind.movies),
    2 => const CatalogScreen(kind: ContentKind.series),
    3 => SearchScreen(focusNode: _searchField),
    _ => const DownloadsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    // Dépendance à la route : reconstruit quand l'accueil revient devant.
    final current = ModalRoute.of(context)?.isCurrent ?? false;
    _pauseIndexes(!current);
    if (current) _offerUpdate();
    // Retour (Android, télécommande, Échap) depuis un autre onglet : revient
    // à l'Accueil. Seul l'Accueil quitte l'app ; sur TV, au 2e appui.
    final tv = ref.watch(televisionProvider);
    return PopScope(
      canPop: _index == 0 && (!tv || _exitArmed != null),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index == 0) {
          _armExit();
          return;
        }
        _select(0);
        // Sur TV, le focus suit : l'onglet quitté est caché, il le perdrait.
        if (ref.read(televisionProvider)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focusTab();
          });
        }
      },
      child: _shell(context),
    );
  }

  Widget _shell(BuildContext context) {
    final tabs = _shown;
    final body = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < tabs.length; i++)
          _visited.contains(i)
              ? _built.putIfAbsent(i, () => _tab(i))
              : const SizedBox.shrink(),
      ],
    );
    if (MediaQuery.sizeOf(context).width >= railMinWidth) {
      final television = ref.watch(televisionProvider);
      Widget zone(
        FocusScopeNode node,
        FocusOnKeyEventCallback onKey,
        Widget child,
      ) => television
          // La zone elle-même n'est pas une étape des flèches, ses éléments si.
          ? FocusScope(
              node: node,
              skipTraversal: true,
              onKeyEvent: onKey,
              child: child,
            )
          : child;
      return Scaffold(
        body: Row(
          children: [
            zone(
              _rail,
              _railKey,
              // Peu de hauteur (fenêtre basse, clavier ouvert) : le rail défile
              // au lieu de superposer les réglages aux onglets.
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: NavigationRail(
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
                          for (final (icon, selected, label, key) in tabs)
                            NavigationRailDestination(
                              icon: _tabIcon(icon, 56, key),
                              selectedIcon: _tabIcon(selected, 56),
                              label: Text(label),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: zone(_content, _contentKey, body)),
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
          for (final (icon, selected, label, key) in tabs)
            NavigationDestination(
              icon: _tabIcon(icon, 64, key),
              selectedIcon: _tabIcon(selected, 64),
              label: label,
            ),
        ],
      ),
    );
  }
}
