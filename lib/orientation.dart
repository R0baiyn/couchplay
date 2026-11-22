import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'television.dart';

/// L'app tourne sur un téléphone ([isPhone]) : hors du lecteur, l'écran
/// reste en portrait (D-060). Fourni par `main()`.
final phoneProvider = Provider<bool>((ref) => false);

/// Un téléphone : Android hors TV, écran [display] (en dp) dont le petit
/// côté fait moins de 600 dp. C'est le seuil de Material entre téléphone et
/// tablette, celui de [railMinWidth] : une tablette de 7 ou 8″ le dépasse,
/// et ce côté ne change pas quand l'écran tourne. Taille inconnue (vide) :
/// pas un téléphone, pour ne jamais bloquer une tablette.
bool isPhone(Size display, {required bool android, bool television = false}) =>
    android &&
    !television &&
    !display.isEmpty &&
    display.shortestSide < railMinWidth;

/// Orientations permises : dans le lecteur sur mobile, paysage (comme
/// avant) ; hors du lecteur, portrait seul sur téléphone, sinon aucune
/// contrainte (liste vide : celles du système).
List<DeviceOrientation> allowedOrientations({
  required bool phone,
  required bool player,
}) => player
    ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
    : phone
    ? const [DeviceOrientation.portraitUp]
    : const [];
