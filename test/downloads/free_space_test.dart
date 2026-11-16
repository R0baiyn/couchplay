import 'dart:io';

import 'package:couchplay/downloads/free_space.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Windows (poste de Robin) et Linux 64 bits (CI) savent la lire.
  test('place libre du dossier temporaire : lue, non nulle', () async {
    final free = await freeSpace(Directory.systemTemp);
    expect(free, isNotNull);
    expect(free, greaterThan(0));
  });
}
