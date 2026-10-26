import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/accounts/server_session.dart';
import 'package:couchplay/app.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
        child: const MaterialApp(home: HomeGate()),
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
    // Laisse le faux serveur et le stockage répondre.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('premier lancement : écran de connexion, User-Agent prérempli', (
    tester,
  ) async {
    server = FakeAdapter.replying(activeAccountJson);
    await pumpApp(tester);

    expect(find.text('Ajouter un compte'), findsOneWidget);
    expect(find.text(defaultUserAgent), findsOneWidget);
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

  testWidgets('connexion réussie : compte enregistré, état affiché', (
    tester,
  ) async {
    server = FakeAdapter.replying(activeAccountJson);
    final container = await pumpApp(tester);

    await fillAndSubmit(tester, host: 'HTTP://serveur.com:8080/');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final active = container.read(activeAccountProvider)!;
    expect(active.host, 'http://serveur.com:8080');
    expect(active.name, 'Salon');
    expect(find.text('Actif'), findsOneWidget);
    expect(find.text('Aucune'), findsOneWidget);

    // Relu depuis le stockage, comme au lancement suivant.
    final reopened = await tester.runAsync(AccountStore.open);
    expect(reopened!.current.active, active);
  });
}
