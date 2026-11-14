import 'package:couchplay/player/player_tracks.dart';
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
}
