import 'package:flutter/material.dart';

/// Demande confirmation : « Annuler » ou [action]. Vrai seulement si
/// [action] est choisie. Le focus va d'abord sur « Annuler » avec
/// [focusCancel], sur [action] avec [focusAction].
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
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            autofocus: focusCancel,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            autofocus: focusAction,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
