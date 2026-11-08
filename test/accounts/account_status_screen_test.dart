import 'package:couchplay/accounts/account.dart';
import 'package:couchplay/accounts/account_status_screen.dart';
import 'package:couchplay/accounts/account_store.dart';
import 'package:couchplay/accounts/server_session.dart';
import 'package:couchplay/server/server_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';
import '../support/settle.dart';

const _account = Account(
  id: 'a',
  name: 'Salon',
  host: 'http://serveur.com',
  username: 'moi',
  password: 'mdp',
  userAgent: defaultUserAgent,
);

void main() {
  testWidgets('serveur injoignable, puis « Réessayer » affiche l\'abonnement', (
    tester,
  ) async {
    var reachable = false;
    final adapter = FakeAdapter((options) async {
      if (!reachable) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      return ResponseBody.fromString(activeAccountJson, 200);
    });
    FlutterSecureStorage.setMockInitialValues({});
    final store = await tester.runAsync(() async {
      final store = await AccountStore.open();
      await store.save(const AccountsState().withAccount(_account));
      return store;
    });
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
              adapter: adapter,
            ),
          ),
        ],
        child: const MaterialApp(home: AccountStatusScreen()),
      ),
    );
    await settle(tester);

    expect(find.text('Abonnement · Salon'), findsOneWidget);
    expect(find.text('Serveur injoignable'), findsOneWidget);

    reachable = true;
    await tester.tap(find.text('Réessayer'));
    await settle(tester);

    expect(find.text('Réessayer'), findsNothing);
    expect(find.text('Actif'), findsOneWidget);
    expect(find.text('Aucune'), findsOneWidget);
    expect(find.text('0 en cours sur 1 autorisée(s)'), findsOneWidget);
  });
}
