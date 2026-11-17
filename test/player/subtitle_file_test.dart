import 'dart:convert';

import 'package:couchplay/player/subtitle_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sous-titres : extensions sur ordinateur, tous les fichiers sur Android',
    () {
      expect(subtitleExtensions(android: false), [
        'srt',
        'ass',
        'ssa',
        'vtt',
        'sub',
      ]);
      expect(subtitleExtensions(android: true), isNull);
    },
  );

  test('texte des sous-titres : UTF-8, sinon Windows-1252', () {
    expect(decodeSubtitleText(utf8.encode('Été à Noël')), 'Été à Noël');
    expect(decodeSubtitleText(latin1.encode('Été à Noël')), 'Été à Noël');
    expect(decodeSubtitleText(const []), '');
  });
}
