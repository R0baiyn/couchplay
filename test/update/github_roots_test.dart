import 'dart:convert';
import 'dart:io';

import 'package:couchplay/server/cloudflare_dns.dart';
import 'package:couchplay/update/github_roots.dart';
import 'package:couchplay/update/updater.dart';
import 'package:couchplay/update/windows_installer.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// SHA-256 du certificat (DER) contenu dans [pem].
String _fingerprint(String pem) {
  final body = pem
      .split('\n')
      .where((line) => !line.startsWith('-----'))
      .join()
      .replaceAll(RegExp(r'\s'), '');
  return sha256.convert(base64.decode(body)).toString();
}

/// Retient le contexte TLS demandé par le premier client HTTP créé, et coupe
/// la connexion : aucun accès au réseau.
final class _ContextSpy extends HttpOverrides {
  SecurityContext? context;
  HttpClient? client;
  var created = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    this.context = context;
    created++;
    return client = super.createHttpClient(context)
      ..connectionFactory = (_, _, _) =>
          Future.error(const SocketException('hors ligne (test)'));
  }
}

void main() {
  group('racines embarquées', () {
    for (final (name, pem, expected) in [
      (
        'USERTrust ECC',
        userTrustEcc,
        '4ff460d54b9c86dabfbcfc5712e0400d2bed3fbc4d4fbdaa86e06adcd2a9ad7a',
      ),
      (
        'ISRG Root X1',
        isrgRootX1,
        '96bcec06264976f37460779acf28c5a7cfe8a3c0aae11a8ffcee05c0bddf08c6',
      ),
    ]) {
      test('$name : empreinte SHA-256 attendue', () {
        expect(_fingerprint(pem), expected);
      });

      test('$name : se charge sans les racines du système', () {
        expect(
          () =>
              SecurityContext(withTrustedRoots: false)
                  .setTrustedCertificatesBytes(utf8.encode(pem)),
          returnsNormally,
        );
      });
    }

    test('githubContext se construit avec et sans racines du système', () {
      expect(githubContext, returnsNormally);
      expect(() => githubContext(withTrustedRoots: false), returnsNormally);
    });
  });

  test('Updater : l\'adaptateur par défaut porte Updater.context', () async {
    final spy = _ContextSpy();
    await HttpOverrides.runWithHttpOverrides(() async {
      final updater = Updater(
        version: '0.1.0',
        installer: WindowsInstaller(
          portable: false,
          appDir: Directory.systemTemp,
        ),
      );
      await expectLater(updater.check(), throwsA(anything));
    }, spy);
    expect(spy.created, greaterThan(0));
    expect(spy.context, same(Updater.context));
    // Comme dio : une connexion inutilisée se ferme après 3 s, pas 15.
    expect(spy.client!.idleTimeout, const Duration(seconds: 3));
  });

  // Vraies connexions à GitHub, en lecture seule : lancées seulement avec
  // RESEAU=1 (`RESEAU=1 flutter test test/update/github_roots_test.dart`).
  // Elles passent par CloudflareHttpOverrides, comme dans l'app.
  group('réseau', skip: Platform.environment['RESEAU'] != '1', () {
    Future<void> head(String host, SecurityContext context) =>
        HttpOverrides.runWithHttpOverrides(() async {
          final client = HttpClient(context: context)
            ..connectionTimeout = const Duration(seconds: 10);
          try {
            final request = await client.headUrl(Uri.https(host, '/'));
            await (await request.close()).drain<void>();
          } finally {
            client.close(force: true);
          }
        }, CloudflareHttpOverrides());

    for (final host in [
      'api.github.com',
      'github.com',
      'release-assets.githubusercontent.com',
      'objects.githubusercontent.com',
    ]) {
      test('$host : sans racines du système, les racines embarquées '
          'suffisent', () async {
        await head(host, githubContext(withTrustedRoots: false));
      });

      test('$host : sans aucune racine, le certificat est refusé', () async {
        await expectLater(
          head(host, SecurityContext(withTrustedRoots: false)),
          throwsA(isA<HandshakeException>()),
        );
      });
    }
  });
}
