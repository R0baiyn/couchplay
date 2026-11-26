import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'television.dart';

/// Demande confirmation : « Annuler » ou [action]. Vrai seulement si
/// [action] est choisie. Le focus va d'abord sur « Annuler » avec
/// [focusCancel], sur [action] avec [focusAction].
///
/// Ouverte pendant qu'OK ou Entrée est maintenu (maintien sur une tuile à la
/// télécommande), la boîte ignore cette touche jusqu'à la fin du maintien (un
/// relâchement que rien ne suit aussitôt, [heldKeyGap]) : les répétitions ne
/// valident rien, seul un nouvel appui agit.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String content,
  required String action,
  bool focusCancel = false,
  bool focusAction = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => _IgnoreHeldOk(
        child: AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              key: const ValueKey('confirm.cancel'),
              autofocus: focusCancel,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('confirm.action'),
              autofocus: focusAction,
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ),
    ) ??
    false;

class _IgnoreHeldOk extends StatefulWidget {
  const _IgnoreHeldOk({required this.child});

  final Widget child;

  @override
  State<_IgnoreHeldOk> createState() => _IgnoreHeldOkState();
}

class _IgnoreHeldOkState extends State<_IgnoreHeldOk> {
  static bool _isOk(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter;

  /// OK enfoncé et à avaler : celui de l'ouverture, ou un appui qui suit
  /// aussitôt son relâchement.
  var _held = false;

  /// Court après chaque relâchement avalé.
  Timer? _release;

  @override
  void initState() {
    super.initState();
    // Lu à l'ouverture : au premier évènement reçu, la touche peut déjà être
    // relâchée.
    _held = HardwareKeyboard.instance.logicalKeysPressed.any(_isOk);
  }

  @override
  void dispose() {
    _release?.cancel();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (!_isOk(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent && (_release?.isActive ?? false)) _held = true;
    if (!_held) return KeyEventResult.ignored;
    if (event is KeyUpEvent) {
      _held = false;
      _release?.cancel();
      _release = Timer(heldKeyGap, () {});
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _onKey,
    child: widget.child,
  );
}
