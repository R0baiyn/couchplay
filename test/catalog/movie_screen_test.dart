import 'dart:async';

import 'package:couchplay/catalog/catalog_providers.dart';
import 'package:couchplay/catalog/movie_screen.dart';
import 'package:couchplay/catalog/versions.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/server/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_app.dart';
import '../support/fake_downloads.dart';
import '../support/settle.dart';

void main() {
  setUpCatalogApp();

  testWidgets('version sans extension dont la fiche charge : « Lecture » '
      'désactivé, pas « Fichier introuvable »', (tester) async {
    final pending = Completer<MovieDetails>();
    await pumpApp(
      tester,
      openMovies: false,
      overrides: [
        movieDetailsProvider.overrideWith(
          (ref, id) => id == '901'
              ? pending.future
              : Future.value(
                  const MovieDetails(
                    details: Details(name: 'Mirage'),
                    extension: 'mkv',
                  ),
                ),
        ),
      ],
    );
    Navigator.of(tester.element(find.byType(Scaffold).first)).push(
      MaterialPageRoute<void>(
        builder: (_) => const MovieScreen(
          entry: CatalogEntry([
            CatalogItem(
              kind: ContentKind.movies,
              id: '900',
              name: 'Mirage (2020) 4K',
              extension: 'mkv',
            ),
            CatalogItem(
              kind: ContentKind.movies,
              id: '901',
              name: 'Mirage (2020) HD',
            ),
          ]),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('HD'));
    await tester.pump();

    expect(find.text('Fichier introuvable'), findsNothing);
    final play = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Lecture'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(play.onPressed, isNull);
    // Sans fichier connu, rien à télécharger non plus.
    final download = tester.widget<OutlinedButton>(
      find.bySubtype<OutlinedButton>(),
    );
    expect(download.onPressed, isNull);
  });

  testWidgets('« Télécharger » met en file la version affichée', (
    tester,
  ) async {
    final fake = FakeDownloads();
    await pumpApp(
      tester,
      openMovies: false,
      overrides: [downloadsProvider.overrideWith(() => fake)],
    );
    Navigator.of(tester.element(find.byType(Scaffold).first)).push(
      MaterialPageRoute<void>(
        builder: (_) => const MovieScreen(
          entry: CatalogEntry([
            CatalogItem(
              kind: ContentKind.movies,
              id: '900',
              name: 'Mirage (2020) 4K',
              extension: 'mkv',
            ),
            CatalogItem(
              kind: ContentKind.movies,
              id: '902',
              name: 'Mirage (2020) HD',
              extension: 'mp4',
            ),
          ]),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('HD'));
    await settle(tester);
    await tester.tap(find.text('Télécharger'));
    await tester.pump();

    expect(fake.calls, ['add movie:902']);
  });
}
