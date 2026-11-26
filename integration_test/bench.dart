// Banc des parcours de bout en bout : la vraie app Windows (fenêtre, libmpv)
// sur un faux serveur local, des dossiers temporaires et un coffre simulé.
// Rien n'est lu ni écrit dans les vrais dossiers de l'app ni dans son coffre.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/catalog/catalog_index.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/logging.dart';
import 'package:couchplay/main.dart';
import 'package:couchplay/server/cloudflare_dns.dart';
import 'package:couchplay/server/models.dart';
import 'package:couchplay/update/updater.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// Port du banc : ni 18080 ni 18095, pris par le banc des émulateurs.
const benchPort = 18097;

/// Identifiants du compte d'essai (faux serveur : mot de passe quelconque).
const benchUser = 'demo';
const benchPassword = 'abc';

/// Version de l'app d'essai : toute release publiée est plus récente.
const benchVersion = '0.0.0';

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

/// Attend que [finder] trouve un seul widget, sur la page du dessus, entrée
/// en entier : pendant une transition, la page qui part et celle qui arrive
/// sont toutes deux à l'écran.
Future<void> waitSettled(WidgetTester tester, Finder finder) =>
    waitUntil(tester, () {
      if (finder.evaluate().length != 1) return false;
      final route = ModalRoute.of(tester.element(finder));
      return route != null &&
          route.isCurrent &&
          route.animation?.status == AnimationStatus.completed;
    }, what: 'transition finie : $finder');

/// `pageBack` une fois la transition précédente finie (sinon deux boutons
/// Retour sont à l'écran).
Future<void> settledPageBack(WidgetTester tester) async {
  await waitSettled(tester, find.byTooltip('Back'));
  await tester.pageBack();
}

/// Fait tourner l'app en temps réel pendant [duration].
Future<void> runFor(WidgetTester tester, Duration duration) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < duration) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

/// Secondes affichées par le texte `m:ss` ou `h:mm:ss` de la Key [key].
int shownSeconds(WidgetTester tester, String key) {
  final text = tester.widget<Text>(byKey(key)).data!;
  return text.split(':').fold(0, (total, part) => total * 60 + int.parse(part));
}

/// Les contrôles du lecteur se masquent seuls pendant la lecture : la souris
/// sur l'image les réaffiche (survol), sans les basculer comme un clic.
Future<TestGesture> showPlayerControls(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: tester.getCenter(byKey('player.video')));
  await mouse.moveBy(const Offset(1, 1));
  await tester.pump();
  return mouse;
}

/// Sans compte : remplit le formulaire avec le compte « Salon » du faux
/// serveur et attend l'Accueil. [user] choisit son comportement.
Future<void> addBenchAccount(
  WidgetTester tester,
  FakeServer server, {
  String user = benchUser,
}) async {
  await waitFor(tester, byKey('accounts.name'));
  expect(find.text('Ajouter un compte'), findsOneWidget);
  await tester.enterText(byKey('accounts.name'), 'Salon');
  await tester.enterText(byKey('accounts.host'), server.host);
  await tester.enterText(byKey('accounts.username'), user);
  await tester.enterText(byKey('accounts.password'), benchPassword);
  await tester.tap(byKey('accounts.submit'));
  // L'onglet choisi perd sa Key (icône choisie sans Key) : l'Accueil se
  // reconnaît aux autres onglets, le formulaire fermé.
  await waitFor(tester, byKey('shell.tabMovies'));
  expect(byKey('accounts.submit'), findsNothing);
}

/// Onglet Films : première catégorie, puis fiche du premier film.
Future<void> openFirstMovie(WidgetTester tester) async {
  await tester.tap(byKey('shell.tabMovies'));
  final tiles = byKeyPrefix('catalog.categoryTile.');
  final picker = byKey('catalog.categoryPicker');
  await waitUntil(
    tester,
    () => tiles.evaluate().isNotEmpty || picker.evaluate().isNotEmpty,
    what: 'liste des catégories de films',
  );
  if (tiles.evaluate().isNotEmpty) {
    await tester.tap(tiles.first);
  } else {
    await tester.tap(picker);
    final sheetTile = byKeyPrefix('catalog.categorySheetTile.');
    await waitFor(tester, sheetTile);
    await tester.tap(sheetTile.first);
  }
  final posters = byKeyPrefix('catalog.poster.movies-');
  await waitFor(tester, posters);
  await tester.tap(posters.first);
  await waitFor(tester, byKey('catalog.play'));
}

/// Attend que la lecture avance (position > 0), sans erreur du lecteur.
Future<void> waitPlaying(WidgetTester tester) async {
  await waitUntil(
    tester,
    // L'erreur remplace la position : on ne lit celle-ci que si elle est là.
    () =>
        byKey('player.error').evaluate().isNotEmpty ||
        (byKey('player.elapsed').evaluate().isNotEmpty &&
            shownSeconds(tester, 'player.elapsed') > 0),
    what: 'la lecture avance',
  );
  expect(byKey('player.error'), findsNothing);
}

/// Lance l'app comme `main`, mais sur des dossiers temporaires et un coffre
/// simulé vide (donc sans compte). Tout est démonté et effacé à la fin du
/// test, journal compris ([journalFile] : `support/couchplay.log`). Sans
/// [updater], pas de mise à jour (comme un build local). Rend l'app lancée :
/// son conteneur, et son arrêt, qui permet un 2e démarrage dans le même test
/// (sinon fait à la fin du test).
Future<IsolatedApp> startIsolatedApp(
  WidgetTester tester, {
  Updater? updater,
}) async {
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
    version: benchVersion,
    television: false,
    updater: updater,
  );
  var stopped = false;
  Future<void> stop() async {
    if (stopped) return;
    stopped = true;
    // Démonter l'app, attendre la fin de l'arrêt du flux (il écrit encore
    // dans `downloadHoldsProvider`), puis seulement jeter les providers.
    try {
      // Le préchargement du catalogue (Accueil) écrit son cache dans un
      // isolate après chaque réponse : un fichier encore ouvert empêcherait
      // d'effacer le dossier (Windows). Attendu avant de démonter l'app.
      await waitUntil(
        tester,
        () => ContentKind.values.every((kind) {
          final index = catalogIndexProvider(kind);
          return !container.read(index.exists) ||
              !container.read(index).isLoading;
        }),
        what: 'fin du préchargement du catalogue',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await waitUntil(
        tester,
        () => !container.read(downloadHoldsProvider).streaming,
        what: 'arrêt du flux du lecteur',
      );
    } finally {
      container.dispose();
      // La sortie du lecteur enregistre la position dans un isolate : le
      // fichier encore ouvert empêcherait d'effacer le dossier (Windows).
      await SerialFileWriter.flushAll();
      // Le journal de l'app est dans `support` : fermé avant l'effacement.
      await closeJournal();
      await _deleteWithRetries(root);
    }
  }

  addTearDown(stop);
  await tester.pump();
  return (container: container, stop: stop);
}

/// Efface [dir] : sous Windows, un fichier qu'un isolate vient de fermer peut
/// rester tenu un instant (`PathAccessException`). Quelques essais courts, puis
/// la dernière erreur est levée : un dossier qui résiste reste un échec.
Future<void> _deleteWithRetries(Directory dir) async {
  for (var attempt = 1; ; attempt++) {
    try {
      await dir.delete(recursive: true);
      return;
    } on PathAccessException {
      if (attempt == 5) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}

/// L'app lancée par [startIsolatedApp].
typedef IsolatedApp = ({
  ProviderContainer container,
  Future<void> Function() stop,
});

/// Le faux serveur Python (`tools/faux-serveur.py`), lancé pour le banc.
final class FakeServer {
  FakeServer._(this._process, this.port, this._output);

  final Process _process;
  final int port;

  /// Sortie du serveur : une ligne par requête reçue.
  final StringBuffer _output;

  /// Nombre de requêtes `GET` reçues pour [path].
  int requests(String path) => 'GET $path '.allMatches('$_output').length;

  /// Adresse à saisir dans le formulaire de compte : jamais de nom à
  /// résoudre, donc jamais de sortie sur le réseau.
  String get host => 'http://${InternetAddress.loopbackIPv4.address}:$port';

  /// [live] : catalogue des fixtures (chaînes 9001 et suivantes), mire du
  /// direct et ancien flux coupé 2 s après une 2e connexion du compte.
  static Future<FakeServer> start({
    int port = benchPort,
    bool live = false,
  }) async {
    final root = _repositoryRoot();
    String inRepository(String folder, String name) =>
        [root.path, folder, name].join(Platform.pathSeparator);
    final video = File(inRepository('probe', 'mire-720p.mkv'));
    final mire = File(inRepository('probe', 'mire-720p.ts'));
    for (final file in [video, if (live) mire]) {
      if (!file.existsSync()) {
        throw StateError(
          'Vidéo du banc absente : ${file.path}. Fichier local ignoré par '
          'git : ces parcours ne tournent que sur le PC qui l’a.',
        );
      }
    }
    if (await _listening(port)) {
      throw StateError(
        'Le port $port est déjà pris : arrêter le processus qui le tient '
        '(un faux serveur oublié ?) avant de relancer.',
      );
    }
    // Sans shell : `kill` atteint python lui-même, pas un cmd.exe. `pythonw` :
    // sans console, donc aucune fenêtre ; sortie, entrée et code de retour
    // passent par les mêmes tubes.
    final process = await Process.start('pythonw', [
      '-I',
      inRepository('tools', 'faux-serveur.py'),
      '--port',
      '$port',
      '--video',
      video.path,
      '--max-par-categorie',
      '20',
      // Banc tué avant `stop` : le serveur voit son entrée se fermer et
      // libère le port.
      '--arret-fin-entree',
      if (live) ...[
        '--donnees',
        inRepository('test', 'fixtures'),
        '--direct',
        mire.path,
        '--delai-coupure',
        '2',
      ],
    ], workingDirectory: root.path);
    final output = StringBuffer();
    process.stdout.transform(utf8.decoder).listen(output.write);
    process.stderr.transform(utf8.decoder).listen(output.write);
    int? exited;
    unawaited(process.exitCode.then((code) => exited = code));
    final server = FakeServer._(process, port, output);
    final clock = Stopwatch()..start();
    while (!await server._answers()) {
      if (exited != null) {
        throw StateError('Le faux serveur s’est arrêté ($exited) : $output');
      }
      if (clock.elapsed > const Duration(seconds: 20)) {
        // L'arrêt qui échoue ne doit pas cacher la sortie du serveur.
        await server.stop().catchError((_) {});
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
      // Borné en entier : un port qui accepte sans répondre ne bloque pas.
      return await () async {
        final request = await client.getUrl(
          Uri.parse(
            '$host/player_api.php?username=$benchUser&password=$benchPassword',
          ),
        );
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode == HttpStatus.ok;
      }().timeout(const Duration(seconds: 2));
    } on IOException {
      return false;
    } on TimeoutException {
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
