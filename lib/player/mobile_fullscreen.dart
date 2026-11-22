import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../orientation.dart';

/// Lecteur sur mobile : plein écran en paysage tant qu'il est affiché, puis
/// barres du système et orientations de l'app à sa sortie (portrait seul sur
/// [phone]). Remplace `defaultEnterNativeFullscreen` de media_kit, qui rend
/// toutes les orientations à la sortie.
class MobileFullscreen extends StatefulWidget {
  const MobileFullscreen({super.key, required this.phone, required this.child});

  final bool phone;
  final Widget child;

  @override
  State<MobileFullscreen> createState() => _MobileFullscreenState();
}

class _MobileFullscreenState extends State<MobileFullscreen> {
  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      ),
    );
    unawaited(
      SystemChrome.setPreferredOrientations(
        allowedOrientations(phone: widget.phone, player: true),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      ),
    );
    unawaited(
      SystemChrome.setPreferredOrientations(
        allowedOrientations(phone: widget.phone, player: false),
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
