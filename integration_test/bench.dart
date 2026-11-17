// Banc des parcours de bout en bout : la vraie app Windows (fenêtre, libmpv)
// sur un faux serveur local, des dossiers temporaires et un coffre simulé.
// Rien n'est lu ni écrit dans les vrais dossiers de l'app ni dans son coffre.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/main.dart';
import 'package:couchplay/server/cloudflare_dns.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// Port du banc : ni 18080 ni 18095, pris par le banc des émulateurs.
const benchPort = 18097;

/// Identifiants du compte d'essai (faux serveur : mot de passe quelconque).
const benchUser = 'demo';
const benchPassword = 'abc';

Finder byKey(String key) => find.byKey(ValueKey(key));

/// Les widgets dont la Key commence par [prefix] (élément de liste dont
/// l'id n'est pas connu d'avance, ex. `catalog.poster.movies-`).
Finder byKeyPrefix(String prefix) => find.byWidgetPredicate(
  (widget) => switch (widget.key) {
    ValueKey<String>(:final value) => value.startsWith(prefix),
    _ => false,
  },
);

/// Fait tourner l'app en temps réel jusqu'à ce que [finder] trouve un widget.
/// Pas de `pumpAndSettle` : une roue de chargement ou une vidéo ne
/// s'arrêtent jamais.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) => waitUntil(
  tester,
  () => finder.evaluate().isNotEmpty,
  timeout: timeout,
  what: '$finder',
);

/// Fait tourner l'app en temps réel jusqu'à ce que [done] soit vrai.
Future<void> waitUntil(
  WidgetTester tester,
  bool Function() done, {
  required String what,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final clock = Stopwatch()..start();
  while (!done()) {
    if (clock.elapsed > timeout) {
      final shown = [
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          ?text.data,
      ];
      fail(
        'Attente dépassée (${timeout.inSeconds} s) : $what\n'
        'Textes affichés : ${shown.join(' | ')}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

/// Fait tourner l'app en temps réel pendant [duration].
Future<void> runFor(WidgetTester tester, Duration duration) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < duration) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

/// Lance l'app comme `main`, mais sur des dossiers temporaires et un coffre
/// simulé vide (donc sans compte). Tout est démonté et effacé à la fin du
/// test.
Future<void> startIsolatedApp(WidgetTester tester) async {
  HttpOverrides.global = CloudflareHttpOverrides();
  MediaKit.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  final root = await Directory.systemTemp.createTemp('couchplay_banc_');
  final support = Directory('${root.path}${Platform.pathSeparator}support');
  final downloads = Directory('${root.path}${Platform.pathSeparator}cache');
  await support.create();
  final container = startApp(
    accounts: await AccountStore.open(),
    support: support,
    downloads: downloads,
    version: '0.0.0',
    television: false,
  );
  addTearDown(() async {
    // Démonter l'app, attendre la fin de l'arrêt du flux (il écrit encore
    // dans `downloadHoldsProvider`), puis seulement jeter les providers.
    await tester.pumpWidget(const SizedBox.shrink());
    await waitUntil(
      tester,
      () => !container.read(downloadHoldsProvider).streaming,
      what: 'arrêt du flux du lecteur',
    );
    container.dispose();
    await root.delete(recursive: true);
  });
  await tester.pump();
}

/// Le faux serveur Python (`tools/faux-serveur.py`), lancé pour le banc.
final class FakeServer {
  FakeServer._(this._process, this.port);

  final Process _process;
  final int port;

  /// Adresse à saisir dans le formulaire de compte : jamais de nom à
  /// résoudre, donc jamais de sortie sur le réseau.
  String get host => 'http://${InternetAddress.loopbackIPv4.address}:$port';

  static Future<FakeServer> start({int port = benchPort}) async {
    final root = _repositoryRoot();
    final video = File(
      [root.path, 'probe', 'mire-720p.mkv'].join(Platform.pathSeparator),
    );
    if (!video.existsSync()) {
      throw StateError(
        'Vidéo du banc absente : ${video.path}. Fichier local ignoré par git : '
        'ces parcours ne tournent que sur le PC qui l’a.',
      );
    }
    if (await _listening(port)) {
      throw StateError(
        'Le port $port est déjà pris : arrêter le processus qui le tient '
        '(un faux serveur oublié ?) avant de relancer.',
      );
    }
    // Sans shell : `kill` atteint python lui-même, pas un cmd.exe.
    final process = await Process.start('python', [
      '-I',
      [root.path, 'tools', 'faux-serveur.py'].join(Platform.pathSeparator),
      '--port',
      '$port',
      '--video',
      video.path,
      '--max-par-categorie',
      '20',
    ], workingDirectory: root.path);
    final output = StringBuffer();
    process.stdout.transform(utf8.decoder).listen(output.write);
    process.stderr.transform(utf8.decoder).listen(output.write);
    int? exited;
    unawaited(process.exitCode.then((code) => exited = code));
    final server = FakeServer._(process, port);
    final clock = Stopwatch()..start();
    while (!await server._answers()) {
      if (exited != null) {
        throw StateError('Le faux serveur s’est arrêté ($exited) : $output');
      }
      if (clock.elapsed > const Duration(seconds: 20)) {
        await server.stop();
        throw StateError('Le faux serveur ne répond pas : $output');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return server;
  }

  /// Arrête le serveur et attend la fin du processus.
  Future<void> stop() async {
    _process.kill();
    await _process.exitCode.timeout(const Duration(seconds: 10));
  }

  Future<bool> _answers() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(
        Uri.parse(
          '$host/player_api.php?username=$benchUser&password=$benchPassword',
        ),
      );
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode == HttpStatus.ok;
    } on IOException {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<bool> _listening(int port) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 1),
      );
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    }
  }

  /// Le dossier du dépôt (celui de `pubspec.yaml`), cherché depuis le
  /// dossier courant puis depuis l'exécutable de l'app d'essai.
  static Directory _repositoryRoot() {
    for (final start in [
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ]) {
      for (Directory? dir = start.absolute; dir != null;) {
        final tool = File(
          [dir.path, 'tools', 'faux-serveur.py'].join(Platform.pathSeparator),
        );
        if (tool.existsSync()) return dir;
        final parent = dir.parent;
        dir = parent.path == dir.path ? null : parent;
      }
    }
    throw StateError('Dépôt introuvable (tools/faux-serveur.py)');
  }
}
