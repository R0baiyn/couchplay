import 'package:flutter/material.dart';

import 'focus_ring.dart';
import 'settings/settings_screen.dart';
import 'television.dart';

/// Onglets de l'accueil : icône, icône choisie, libellé, Key.
typedef ShellTab = (IconData, IconData, String, Key);

/// L'icône d'un onglet, à la taille de sa pastille ([width] × 32) : comme
/// le bouton Réglages du rail, l'anneau entoure la pastille, pas le libellé.
Widget _tabIcon(IconData icon, double width, [Key? key]) => FocusRing(
  key: key,
  hug: true,
  radius: 16,
  child: SizedBox(width: width, height: 32, child: Icon(icon)),
);

const List<ShellTab> shellTabs = [
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

/// Rail des onglets (grand écran).
class ShellRail extends StatelessWidget {
  const ShellRail({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<ShellTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    // Peu de hauteur (fenêtre basse, clavier ouvert) : le rail défile
    // au lieu de superposer les réglages aux onglets.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelect,
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
    );
  }
}

/// Barre des onglets (écran étroit).
class ShellBottomBar extends StatelessWidget {
  const ShellBottomBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<ShellTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelect,
      destinations: [
        for (final (icon, selected, label, key) in tabs)
          NavigationDestination(
            icon: _tabIcon(icon, 64, key),
            selectedIcon: _tabIcon(selected, 64),
            label: label,
          ),
      ],
    );
  }
}

/// Sur TV, le rail et l'onglet sont deux zones : ← au bord gauche de
/// l'onglet revient à l'onglet choisi du rail, → depuis le rail revient au
/// dernier élément visité de l'onglet, et les bouts du rail le gardent.
/// Sans elles, les flèches visent l'élément le plus proche à l'écran (le
/// bouton des réglages, une affiche coupée en haut).
class ShellZones {
  ShellZones({required this.selectedIndex});

  /// Index de l'onglet choisi.
  final int Function() selectedIndex;

  final rail = FocusScopeNode(debugLabel: 'rail');
  final content = FocusScopeNode(debugLabel: 'onglet');

  void dispose() {
    rail.dispose();
    content.dispose();
  }

  /// Les éléments que les flèches atteignent dans [scope], de haut en bas
  /// puis de gauche à droite.
  static List<FocusNode> _reachable(FocusScopeNode scope) =>
      scope.traversalDescendants.where((node) => node.canRequestFocus).toList()
        ..sort((a, b) {
          final top = a.rect.top.compareTo(b.rect.top);
          return top != 0 ? top : a.rect.left.compareTo(b.rect.left);
        });

  KeyEventResult railKey(FocusNode _, KeyEvent event) {
    if (arrowDirection(event) != TraversalDirection.right) {
      return KeyEventResult.ignored;
    }
    final last = content.focusedChild;
    if (last != null && last.canRequestFocus) {
      last.requestFocus();
    } else {
      // Première visite : le contenu (une affiche) plutôt que les boutons
      // de l'en-tête (« Actualiser », en haut à droite).
      final reachable = _reachable(content);
      bool inHeader(FocusNode node) =>
          node.context?.findAncestorWidgetOfExactType<AppBar>() != null;
      (reachable.where((node) => !inHeader(node)).firstOrNull ??
              reachable.firstOrNull)
          ?.requestFocus();
    }
    return KeyEventResult.handled;
  }

  KeyEventResult contentKey(FocusNode _, KeyEvent event) {
    final direction = arrowDirection(event);
    if (direction == null) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus;
    // La zone elle-même a le focus : l'élément qui l'avait a disparu (liste
    // vidée, tuile retirée). Une flèche le redonne au premier élément de
    // l'onglet, ou au rail s'il n'y en a aucun : sinon la télécommande ne
    // répondrait plus.
    if (focused is FocusScopeNode) {
      final first = _reachable(content).firstOrNull;
      if (first != null) {
        first.requestFocus();
      } else {
        focusTab();
      }
      return KeyEventResult.handled;
    }
    if (direction != TraversalDirection.left) return KeyEventResult.ignored;
    if (focused == null || !focused.focusInDirection(TraversalDirection.left)) {
      focusTab();
    }
    return KeyEventResult.handled;
  }

  /// L'onglet choisi, dans le rail.
  void focusTab() {
    // Les onglets d'abord, de haut en bas, puis les réglages.
    final tabs = _reachable(rail);
    final index = selectedIndex();
    if (index < tabs.length) tabs[index].requestFocus();
  }
}
