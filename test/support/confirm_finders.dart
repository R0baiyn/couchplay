import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les deux boutons de la boîte de `confirm()` (lib/confirm.dart), trouvés par
/// leur type tant que ce fichier racine n'a pas de Keys (plan S037).
final confirmCancel = find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextButton),
);
final confirmAction = find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(FilledButton),
);
