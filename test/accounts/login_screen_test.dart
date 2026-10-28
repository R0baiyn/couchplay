import 'dart:io';

import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_files.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/accounts/login_screen.dart';
import 'package:couchplay/accounts/server_session.dart';
import 'package:couchplay/app.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

void main() {
  late FakeAdapter server;

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    final store = await tester.runAsync(AccountStore.open);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountStoreProvider.overrideWithValue(store!),
          accountFilesProvider.overrideWithValue(
            AccountFiles(Directory.systemTemp.createTempSync('couchplay_')),
          ),
          serverClientFactoryProvider.overrideWithValue(
            (account) => ServerClient(
              host: account.host,
              username: account.username,
              password: account.password,
              userAgent: account.userAgent,
              adapter: server,
            ),
          ),
        ],
        // L'app entière : ses raccourcis (télécommande) comptent.
        child: const CouchPlayApp(home: HomeGate()),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.byType(HomeGate)));
  }

  Future<void> fillAndSubmit(
    WidgetTester tester, {
    required String host,
  }) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Salon');
    await tester.enterText(fields.at(1), host);
    await tester.enterText(fields.at(2), 'moi');
    await tester.enterText(fields.at(3), 'mdp');
    await tester.tap(find.text('Se connecter'));
    // Laisse le faux serveur et le stockage répondre. Pas de pumpAndSettle :
    // après la connexion, le catalogue tourne avec une roue de chargement.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('premier lancement : écran de connexion, User-Agent prérempli', (
    tester,
  ) async {
    server = FakeAdapter.replying(activeAccountJson);
    await pumpApp(tester);

    expect(find.text('Ajouter un compte'), findsOneWidget);
    expect(find.text(defaultUserAgent), findsOneWidget);
  });

  testWidgets('télécommande : ↓ et ↑ passent d\'un champ à l\'autre', (
    tester,
  ) async {
    server = FakeAdapter.replying(activeAccountJson);
    await pumpApp(tester);
    final fields = find.byType(EditableText);
    bool focusedAt(int index) =>
        tester.widget<EditableText>(fields.at(index)).focusNode.hasFocus;

    // Le premier champ a le focus dès l'ouverture : rien à toucher (TV).
    expect(focusedAt(0), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedAt(1), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focusedAt(0), isTrue);
  });

  testWidgets('hôte invalide : refusé avant tout appel réseau', (tester) async {
    server = FakeAdapter.replying(activeAccountJson);
    final container = await pumpApp(tester);

    await fillAndSubmit(tester, host: 'serveur.com/player_api.php');

    expect(
      find.text('L\'adresse commence par http:// ou https://'),
      findsOneWidget,
    );
    expect(server.calls, 0);
    expect(container.read(accountsProvider).accounts, isEmpty);
  });

  testWidgets('identifiants refusés : message, compte non enregistré', (
    tester,
  ) async {
    server = FakeAdapter.replying('{"user_info":{"auth":0}}');
    final container = await pumpApp(tester);

    await fillAndSubmit(tester, host: 'http://serveur.com:8080');

    expect(find.text('Identifiants refusés'), findsOneWidget);
    expect(container.read(accountsProvider).accounts, isEmpty);
  });

  testWidgets('serveur injoignable : message, compte non enregistré', (
    tester,
  ) async {
    server = FakeAdapter.failing(DioExceptionType.connectionError);
    final container = await pumpApp(tester);

    await fillAndSubmit(tester, host: 'http://serveur.com:8080');

    expect(find.text('Serveur injoignable'), findsOneWidget);
    expect(container.read(accountsProvider).accounts, isEmpty);
  });

  testWidgets('connexion réussie : compte enregistré, catalogue affiché', (
    tester,
  ) async {
    server = FakeAdapter.replying(activeAccountJson);
    final container = await pumpApp(tester);

    await fillAndSubmit(tester, host: 'HTTP://serveur.com:8080/');

    final active = container.read(activeAccountProvider)!;
    expect(active.host, 'http://serveur.com:8080');
    expect(active.name, 'Salon');
    // L'app passe aux onglets du catalogue.
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    // Relu depuis le stockage, comme au lancement suivant.
    final reopened = await tester.runAsync(AccountStore.open);
    expect(reopened!.current.active, active);
  });
}
