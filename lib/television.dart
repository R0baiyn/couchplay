import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// L'app tourne sur une TV (Android TV, Google TV) : la télécommande y est
/// la seule saisie, et le clavier à l'écran couvre la moitié de l'image.
/// Fourni par `main()`.
final televisionProvider = Provider<bool>((ref) => false);

/// Demandé à Android (`MainActivity.kt`) au démarrage.
Future<bool> isTelevision() async {
  if (!Platform.isAndroid) return false;
  const channel = MethodChannel('couchplay/device');
  return await channel.invokeMethod<bool>('isTelevision') ?? false;
}
