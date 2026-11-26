// Point d'entrée unique des parcours de bout en bout (Docs/FEATURES.md §5).
// Lancement : flutter test integration_test -d windows (vraie fenêtre).
// Un seul fichier `_test` : sous Windows, l'app du 2e fichier ne démarre pas
// (« Error waiting for a debug connection »). Chaque parcours est un groupe
// avec son faux serveur, ses dossiers temporaires et son compte neufs.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'journey_1.dart' as journey_1;
import 'journey_2.dart' as journey_2;
import 'journey_3.dart' as journey_3;
import 'journey_4.dart' as journey_4;
import 'journey_5.dart' as journey_5;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('parcours 1', journey_1.main);
  group('parcours 2', journey_2.main);
  group('parcours 3', journey_3.main);
  group('parcours 4', journey_4.main);
  group('parcours 5', journey_5.main);
}
