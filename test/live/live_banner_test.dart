import 'package:couchplay/format.dart';
import 'package:couchplay/live/channel.dart';
import 'package:couchplay/live/guide.dart';
import 'package:couchplay/live/live_banner.dart';
import 'package:couchplay/live/live_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixed_guide.dart';

void main() {
  final origin = DateTime.utc(2026, 11, 24, 12);
  final guide = Guide(
    channels: const {'a.fr', 'vide.fr'},
    programmes: {
      'a.fr': [
        programmeAt(origin, -1800, 1800, 'Journal'),
        programmeAt(origin, 1800, 3600, 'Météo'),
      ],
    },
  );

  Future<void> pump(WidgetTester tester, Channel channel) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          guideProvider.overrideWith(() => FixedGuide(guide)),
          guideNowProvider.overrideWithValue(() => origin),
        ],
        child: MaterialApp(
          home: Scaffold(body: LiveBanner(channel: channel)),
        ),
      ),
    );
    await tester.pump();
  }

  Finder inBanner(Finder finder) => find.descendant(
    of: find.byKey(const ValueKey('live.player.banner')),
    matching: finder,
  );

  testWidgets('sous le nom : programme en cours, avancement, puis le suivant', (
    tester,
  ) async {
    await pump(
      tester,
      const Channel(id: '1', name: 'Une', number: 1, epgChannelId: 'a.fr'),
    );
    expect(inBanner(find.text('1 · Une')), findsOneWidget);
    expect(inBanner(find.text('Journal')), findsOneWidget);
    expect(
      inBanner(
        find.text(
          '${formatClock(origin.add(const Duration(minutes: 30)))} '
          'Météo',
        ),
      ),
      findsOneWidget,
    );
    final bar = tester.widget<LinearProgressIndicator>(
      inBanner(find.byKey(const ValueKey('live.onAir.progress'))),
    );
    expect(bar.value, 0.5);
  });

  testWidgets('chaîne sans programme ou sans id de guide : le nom seul', (
    tester,
  ) async {
    for (final id in ['vide.fr', null]) {
      await pump(
        tester,
        Channel(id: '2', name: 'Deux', number: 2, epgChannelId: id),
      );
      expect(inBanner(find.text('2 · Deux')), findsOneWidget);
      expect(
        inBanner(find.byKey(const ValueKey('live.onAir'))),
        findsNothing,
        reason: id,
      );
    }
  });
}
