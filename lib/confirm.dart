import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Demande confirmation : « Annuler » ou [action]. Vrai seulement si
/// [action] est choisie. Le focus va d'abord sur « Annuler » avec
/// [focusCancel], sur [action] avec [focusAction].
///
/// Ouverte pendant qu'OK ou Entrée est maintenu (maintien sur une tuile à la
/// télécommande), la boîte ignore cette touche jusqu'à son relâchement : les
/// répétitions ne valident rien, seul un nouvel appui agit.
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

  /// OK déjà enfoncé à l'ouverture : tant qu'il n'est pas relâché, ses
  /// évènements (répétitions, relâchement) sont avalés.
  late var _held = HardwareKeyboard.instance.logicalKeysPressed.any(_isOk);

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (!_held || !_isOk(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyUpEvent) _held = false;
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
