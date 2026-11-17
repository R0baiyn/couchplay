import 'dart:convert';
import 'dart:io';

import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/downloads/downloads_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_app.dart';
import '../support/fake_server.dart';
import '../support/settle.dart';

void main() {
  setUpCatalogApp();

  testWidgets(
    'démarrage sans serveur : l\'onglet s\'ouvre sur les vidéos prêtes',
    (tester) async {
      // Compte présent, serveur injoignable, une vidéo déjà téléchargée.
      server = FakeAdapter.failing(DioExceptionType.connectionError);
      final account = Directory('${root.path}/accounts/compte')
        ..createSync(recursive: true);
      Directory('${root.path}/downloads/compte').createSync(recursive: true);
      File('${root.path}/downloads/compte/movie-1.mkv')
          .writeAsBytesSync(List.filled(2000, 7));
      // L'affiche enregistrée au téléchargement (PNG 1 × 1).
      File('${root.path}/downloads/compte/poster-movie-1').writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
        ),
      );
      const host = 'example.com';
      File('${account.path}/downloads.json').writeAsStringSync('''
{"version":1,"downloads":{"movie:1":{"name":"Mirage","extension":"mkv",
"poster":"http://$host/affiche.jpg",
"size":2000,"received":2000,"status":"ready",
"addedAt":"2026-11-16T10:00:00.000Z"}}}''');

      await pumpApp(
        tester,
        openMovies: false,
        overrides: [
          downloadFilesProvider.overrideWithValue(
            AccountFiles(Directory('${root.path}/downloads')),
          ),
        ],
      );
      await tester.tap(find.byIcon(Icons.download_outlined));
      await settle(tester);

      expect(find.byType(DownloadsScreen), findsOneWidget);
      expect(find.text('Prêts'), findsOneWidget);
      expect(find.text('Mirage'), findsOneWidget);
      expect(find.text('2 Ko'), findsOneWidget);
      // L'affiche lue sur le disque, pas sur le serveur injoignable.
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(DownloadsScreen),
          matching: find.byType(Image),
        ),
      );
      final file = (image.image as ResizeImage).imageProvider as FileImage;
      expect(file.file.path, endsWith('poster-movie-1'));
      expect(tester.takeException(), isNull);
    },
  );
}
