import 'dart:io';

import 'package:flutter/services.dart';

/// Charge les vrais Roboto de Flutter à la place d'Ahem (où chaque lettre
/// fait 12 px de large) : indispensable pour tester qu'un libellé tient sur
/// une ligne. Les fichiers viennent du SDK (`FLUTTER_ROOT`, posé par
/// `flutter test`) ; sans eux, le test échoue avec un message clair.
Future<void> loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    throw StateError('FLUTTER_ROOT absent : lancer par flutter test');
  }
  final fonts = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String name) async =>
      ByteData.sublistView(await File('$fonts/$name').readAsBytes());
  final loader = FontLoader('Roboto')
    ..addFont(read('roboto-regular.ttf'))
    ..addFont(read('roboto-medium.ttf'))
    ..addFont(read('roboto-bold.ttf'));
  await loader.load();
}
