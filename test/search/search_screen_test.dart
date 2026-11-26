import 'dart:async';

import 'package:couchplay/catalog/catalog_index.dart';
import 'package:couchplay/catalog/catalog_repository.dart';
import 'package:couchplay/live/channel.dart';
import 'package:couchplay/live/channel_list_view.dart';
import 'package:couchplay/live/live_player_screen.dart';
import 'package:couchplay/player/playback.dart';
import 'package:couchplay/poster_tile.dart';
import 'package:couchplay/search/search_index.dart';
import 'package:couchplay/server/item_name.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_app.dart';
import '../support/fake_playback.dart';
import '../support/fake_server.dart';
import '../support/settle.dart';

void main() {
  setUpCatalogApp();
  _chipTests();

  testWidgets('Recherche : champ, résultats, rien trouvé, effacer', (
    tester,
  ) async {
    await pumpApp(tester, openMovies: false);
    await tester.tap(find.byKey(const ValueKey('shell.tabSearch')));
    await settle(tester);

    final field = find.byKey(const ValueKey('search.field'));
    Future<void> type(String text) async {
      await tester.enterText(field, text);
      // La recherche part 300 ms après la dernière frappe.
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
    }

    // Champ vide : invitation, pas de croix.
    expect(find.byKey(const ValueKey('search.hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.clear')), findsNothing);

    await type('horizon');
    expect(find.byKey(const ValueKey('search.results')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.sectionMovies')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.hint')), findsNothing);
    expect(find.text('Horizon (2024)'), findsOneWidget);

    await type('veilleurs');
    expect(find.byKey(const ValueKey('search.sectionSeries')), findsOneWidget);

    await type('zzzzqx');
    expect(find.byKey(const ValueKey('search.none')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.results')), findsNothing);

    // La croix vide le champ et revient à l'invitation.
    await tester.tap(find.byKey(const ValueKey('search.clear')));
    await settle(tester);
    expect(find.byKey(const ValueKey('search.hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.clear')), findsNothing);
  });

  Future<void> typeQuery(
    WidgetTester tester,
    String text, {
    bool wait = true,
  }) async {
    // Sans attente : une roue de chargement tourne sans fin, `settle`
    // échouerait.
    Future<void> next() => wait ? settle(tester) : tester.pump();
    await tester.tap(find.byKey(const ValueKey('shell.tabSearch')));
    await next();
    await tester.enterText(find.byKey(const ValueKey('search.field')), text);
    // La recherche part 300 ms après la dernière frappe.
    await tester.pump(const Duration(milliseconds: 300));
    await next();
  }

  testWidgets('Recherche : listes en échec, erreur puis nouvel essai', (
    tester,
  ) async {
    var down = true;
    final routes = {
      '': activeAccountJson,
      'get_vod_categories': fixture('vod_categories'),
      'get_vod_streams': fixture('vod_streams'),
      'get_series_categories': fixture('series_categories'),
      'get_series': fixture('series'),
    };
    server = FakeAdapter((options) async {
      final action = options.uri.queryParameters['action'] ?? '';
      final body = routes[action];
      final listing = action == 'get_vod_streams' || action == 'get_series';
      return body == null || (down && listing)
          ? ResponseBody.fromString('', 500)
          : ResponseBody.fromString(body, 200);
    });
    await pumpApp(tester, openMovies: false);

    await typeQuery(tester, 'horizon');
    expect(find.byKey(const ValueKey('search.error')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.results')), findsNothing);

    down = false;
    await tester.tap(find.byKey(const ValueKey('catalog.errorRetry')));
    await settle(tester);
    expect(find.byKey(const ValueKey('search.error')), findsNothing);
    expect(find.byKey(const ValueKey('search.results')), findsOneWidget);
  });

  testWidgets('films et séries en échec : les chaînes trouvées s\'affichent '
      'quand même', (tester) async {
    final routes = {
      '': activeAccountJson,
      'get_vod_categories': fixture('vod_categories'),
      'get_series_categories': fixture('series_categories'),
    };
    server = FakeAdapter((options) async {
      final body = routes[options.uri.queryParameters['action'] ?? ''];
      return body == null
          ? ResponseBody.fromString('', 500)
          : ResponseBody.fromString(body, 200);
    });
    await pumpApp(
      tester,
      openMovies: false,
      searchChannels: true,
      overrides: [
        channelSearchIndexProvider.overrideWithValue(
          AsyncData([
            (
              channel: const Channel(id: '9011', name: 'Sport 1 FHD'),
              text: normalize('Sport 1 FHD'),
            ),
          ]),
        ),
      ],
    );

    await typeQuery(tester, 'sport');
    expect(find.byKey(const ValueKey('search.error')), findsNothing);
    expect(
      find.byKey(const ValueKey('search.sectionChannels')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('live.channel.9011')), findsOneWidget);
    // Rien trouvé du tout : l'erreur des listes revient.
    await tester.enterText(find.byKey(const ValueKey('search.field')), 'zz');
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(find.byKey(const ValueKey('search.error')), findsOneWidget);
  });

  testWidgets('chaînes encore en chargement : la roue plutôt que « Aucun '
      'résultat » ; les films trouvés n\'attendent pas', (tester) async {
    await pumpApp(
      tester,
      openMovies: false,
      searchChannels: true,
      overrides: [
        channelSearchIndexProvider.overrideWithValue(const AsyncLoading()),
      ],
    );
    await typeQuery(tester, 'zzzz', wait: false);
    expect(find.byKey(const ValueKey('search.loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.none')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('search.field')),
      'horizon',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.byKey(const ValueKey('search.results')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.sectionMovies')), findsOneWidget);
  });

  testWidgets('Recherche : chargement tant que les listes arrivent', (
    tester,
  ) async {
    final gate = Completer<void>();
    await pumpApp(
      tester,
      openMovies: false,
      waitForIndex: false,
      overrides: [
        catalogIndexProvider.overrideWith2((kind) => _GatedIndex(kind, gate)),
      ],
    );

    await typeQuery(tester, 'horizon', wait: false);
    expect(find.byKey(const ValueKey('search.loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('search.results')), findsNothing);

    gate.complete();
    await settle(tester);
    expect(find.byKey(const ValueKey('search.loading')), findsNothing);
    expect(find.byKey(const ValueKey('search.results')), findsOneWidget);
  });

  testWidgets('chaînes visibles trouvées par leur nom, chaque qualité à part ; '
      'OK ouvre le lecteur, zapping dans les chaînes trouvées', (tester) async {
    await pumpApp(
      tester,
      openMovies: false,
      searchChannels: true,
      overrides: [
        playbackProvider.overrideWithValue(fakePlayback(FakePlayer())),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('shell.tabSearch')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('search.field')),
      'chaine 1',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);

    expect(
      find.byKey(const ValueKey('search.sectionChannels')),
      findsOneWidget,
    );
    expect(find.text('Chaînes (3)'), findsOneWidget);
    // HD, FHD et SD ; « Chaîne 10 » (EX-YU) est masquée par le filtre.
    for (final id in ['9001', '9006', '9008']) {
      expect(find.byKey(ValueKey('live.channel.$id')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('live.channel.9020')), findsNothing);
    // Pas de « en cours » : la recherche ne charge pas le guide.
    expect(
      tester
          .widgetList<ChannelTile>(find.byType(ChannelTile))
          .map((t) => t.guide),
      everyElement(isFalse),
    );

    await tester.tap(find.byKey(const ValueKey('live.channel.9006')));
    await tester.pump();
    await tester.pump();
    final player = tester.widget<LivePlayerScreen>(
      find.byType(LivePlayerScreen),
    );
    expect(player.channel.id, '9006');
    expect([for (final c in player.channels) c.id], ['9001', '9006', '9008']);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });
}

// Les deux listes du compte et cette chaîne contiennent « le » : un film,
// une série, une chaîne.
final _soleil = channelSearchIndexProvider.overrideWithValue(
  AsyncData([
    (
      channel: const Channel(id: '9011', name: 'Soleil'),
      text: normalize('Soleil'),
    ),
  ]),
);

Finder _byKey(String key) => find.byKey(ValueKey(key));

Finder _chip(String name) => _byKey('search.filter.$name');

bool _selected(WidgetTester tester, String name) =>
    tester.widget<ChoiceChip>(_chip(name)).selected;

/// Sections affichées, de haut en bas.
List<String> _sections(WidgetTester tester) {
  final shown = {
    for (final name in ['Channels', 'Movies', 'Series'])
      if (_byKey('search.section$name').evaluate().isNotEmpty)
        name: tester.getTopLeft(_byKey('search.section$name')).dy,
  };
  return shown.keys.toList()..sort((a, b) => shown[a]!.compareTo(shown[b]!));
}

/// Assez haut pour que les trois sections soient construites.
Future<void> _searchFor(
  WidgetTester tester,
  String query, {
  List<Override>? overrides,
  bool wait = true,
}) async {
  await pumpApp(
    tester,
    size: const Size(1280, 2400),
    openMovies: false,
    searchChannels: true,
    overrides: overrides ?? [_soleil],
  );
  await tester.tap(_byKey('shell.tabSearch'));
  await settle(tester);
  await tester.enterText(_byKey('search.field'), query);
  await tester.pump(const Duration(milliseconds: 300));
  wait ? await settle(tester) : await tester.pump();
}

Future<void> _tapChip(WidgetTester tester, String name) async {
  await tester.tap(_chip(name));
  await settle(tester);
}

void _chipTests() {
  testWidgets('puces : « Tout » au départ, Films, Séries puis TV ; chacune '
      'ne garde que son type', (tester) async {
    await _searchFor(tester, 'le');
    expect(_selected(tester, 'all'), isTrue);
    expect(_sections(tester), ['Movies', 'Series', 'Channels']);

    await _tapChip(tester, 'movies');
    expect(_selected(tester, 'movies'), isTrue);
    expect(_sections(tester), ['Movies']);
    await _tapChip(tester, 'series');
    expect(_sections(tester), ['Series']);
    await _tapChip(tester, 'live');
    expect(_sections(tester), ['Channels']);
    expect(_byKey('live.channel.9011'), findsOneWidget);
    await _tapChip(tester, 'all');
    expect(_sections(tester), ['Movies', 'Series', 'Channels']);
  });

  testWidgets('puce gardée quand le texte change ; type sans résultat : les '
      'puces restent', (tester) async {
    await _searchFor(tester, 'le');
    await _tapChip(tester, 'series');

    // « horizon » : des films seulement.
    await tester.enterText(_byKey('search.field'), 'horizon');
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(_selected(tester, 'series'), isTrue);
    expect(_byKey('search.noneOfType'), findsOneWidget);
    expect(_sections(tester), isEmpty);

    await _tapChip(tester, 'all');
    expect(_byKey('search.noneOfType'), findsNothing);
    expect(_sections(tester), ['Movies']);
  });

  testWidgets('puce TV pendant le chargement des chaînes : la roue', (
    tester,
  ) async {
    await _searchFor(
      tester,
      'horizon',
      overrides: [
        channelSearchIndexProvider.overrideWithValue(const AsyncLoading()),
      ],
      wait: false,
    );
    await tester.tap(_chip('live'));
    await tester.pump();
    expect(_byKey('search.loading'), findsOneWidget);
    expect(_byKey('search.noneOfType'), findsNothing);
  });

  testWidgets('puces au clavier et à la télécommande : ↑ depuis les '
      'résultats, ← → entre elles, OK choisit', (tester) async {
    await _searchFor(tester, 'le');

    /// Puce qui a le focus, ou null.
    String? focusedChip() {
      final key = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<ChoiceChip>()
          ?.key;
      return key is ValueKey<String> ? key.value.split('.').last : null;
    }

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await settle(tester);
    }

    // Une affiche a le focus : ↑ remonte aux puces.
    Focus.of(
      tester.element(
        find
            .descendant(
              of: find.byType(PosterTile),
              matching: find.byType(Column),
            )
            .first,
      ),
    ).requestFocus();
    await tester.pump();
    await press(LogicalKeyboardKey.arrowUp);
    expect(focusedChip(), isNotNull);
    for (var i = 0; focusedChip() != 'all'; i++) {
      if (i == 4) fail('« Tout » jamais atteinte par ←');
      await press(LogicalKeyboardKey.arrowLeft);
    }
    await press(LogicalKeyboardKey.arrowRight);
    await press(LogicalKeyboardKey.arrowRight);
    expect(focusedChip(), 'series');
    await press(LogicalKeyboardKey.select);
    expect(_selected(tester, 'series'), isTrue);
    expect(_sections(tester), ['Series']);
    expect(focusedChip(), 'series');
    // ↓ redescend dans les résultats.
    await press(LogicalKeyboardKey.arrowDown);
    expect(focusedChip(), isNull);
  });
}

/// Index qui ne se charge qu'à l'ouverture de [gate].
class _GatedIndex extends CatalogIndexNotifier {
  _GatedIndex(super.kind, this.gate);

  final Completer<void> gate;

  @override
  Future<Loaded<KindIndex>> build() async {
    await gate.future;
    return super.build();
  }
}
