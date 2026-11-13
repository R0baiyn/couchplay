import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'accounts/account_store.dart';
import 'accounts/login_screen.dart';
import 'focus_ring.dart';
import 'focus_scroll.dart';
import 'home_shell.dart';
import 'television.dart';

/// L'app, toujours en thème sombre : une salle de cinéma, pas un bureau.
class CouchPlayApp extends StatefulWidget {
  const CouchPlayApp({super.key, required this.home});

  final Widget home;

  @override
  State<CouchPlayApp> createState() => _CouchPlayAppState();
}

class _CouchPlayAppState extends State<CouchPlayApp> {
  static final _dark = ThemeData(
    colorSchemeSeed: Colors.deepPurple,
    brightness: Brightness.dark,
  );

  /// Au clavier et à la télécommande : l'anneau sur l'élément qui a le
  /// focus. Changer de thème avec le mode reconstruit tous les boutons,
  /// même celui qui garde le focus après un toucher.
  static final _keyboard = withFocusRing(_dark);

  static final _navigator = GlobalKey<NavigatorState>();

  /// Télécommande : ↑ ↓ passent d'un élément à l'autre, même depuis un champ
  /// de texte, où Android les garde sinon pour le curseur (le champ d'une
  /// ligne n'en a pas l'usage). Placés sous les raccourcis de texte de
  /// l'app, ils passent avant eux.
  static const _remoteKeys = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
      TraversalDirection.up,
      ignoreTextFields: false,
    ),
    SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
      TraversalDirection.down,
      ignoreTextFields: false,
    ),
  };

  var _mode = FocusManager.instance.highlightMode;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onModeChange);
  }

  void _onModeChange(FocusHighlightMode mode) => setState(() => _mode = mode);

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onModeChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CouchPlay',
      debugShowCheckedModeBanner: false,
      theme: _mode == FocusHighlightMode.traditional ? _keyboard : _dark,
      navigatorKey: _navigator,
      // Échap revient en arrière partout, comme le bouton retour (clavier,
      // télécommande). Placé au-dessus du Navigator, ce raccourci reçoit la
      // touche en dernier : un menu ou un champ qui la gère passe avant.
      builder: (context, child) {
        final app = CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _navigator.currentState?.maybePop(),
          },
          // Encoche, caméra et boutons du téléphone : rien ne passe dessous,
          // surtout en paysage où ils sont sur les côtés. Le haut est géré
          // par les barres d'application.
          child: SafeArea(
            top: false,
            // Accueil et écrans sans groupe propre : défilement doux aussi.
            child: SmoothFocusGroup(child: TvArrowKeys(child: child!)),
          ),
        );
        // Sur ordinateur, ↑ ↓ gardent leur rôle dans un champ (début, fin)
        // et sur un curseur (volume).
        if (defaultTargetPlatform != TargetPlatform.android) return app;
        // Navigation de télécommande : un curseur ne garde que ← →, et ↑ ↓
        // en sortent ; un bouton désactivé reste une étape, sans bloquer.
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(navigationMode: NavigationMode.directional),
          child: Shortcuts(shortcuts: _remoteKeys, child: app),
        );
      },
      home: widget.home,
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
