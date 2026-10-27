import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Attend la fin d'un chargement qui mêle réseau factice, disque et isolates
/// réels : quelques tours de vraie horloge, jusqu'à ce qu'il n'y ait plus de
/// roue de chargement visible ni d'animation (transition de page).
///
/// `pumpAndSettle` ne convient pas : il n'avance que l'horloge factice, et
/// une roue de chargement tourne sans fin.
Future<void> settle(WidgetTester tester) async {
  // Le premier isolate d'un test démarre lentement : jusqu'à 5 s.
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final loading = find
        .byType(CircularProgressIndicator, skipOffstage: true)
        .evaluate();
    if (i > 2 && loading.isEmpty && !tester.binding.hasScheduledFrame) return;
  }
}
