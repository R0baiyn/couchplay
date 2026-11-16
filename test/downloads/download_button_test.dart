import 'package:flutter/services.dart';
import 'package:couchplay/downloads/download.dart';
import 'package:couchplay/downloads/download_button.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/library/library.dart';
import 'package:couchplay/television.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const movie = PlayItem.movie(id: '1', extension: 'mkv', name: 'Mirage');

/// File simulée : garde les entrées données et note les appels.
final class FakeDownloads extends DownloadsNotifier {
  FakeDownloads([this.initial = const {}, this.local = const {}]);

  final Map<String, Download> initial;

  /// Clés qui « se lisent en local ».
  final Set<String> local;
  final calls = <String>[];

  @override
  DownloadsState build() => DownloadsState(entries: initial);

  @override
  Future<void> add(Iterable<PlayItem> items) async =>
      calls.add('add ${items.map((i) => i.key).join(' ')}');

  @override
  Future<void> pause(String key) async => calls.add('pause $key');

  @override
  Future<void> resume(String key) async => calls.add('resume $key');

  @override
  Future<void> remove(String key) async => calls.add('remove $key');

  @override
  Future<void> removeAll() async => calls.add('removeAll');
}

Download download(
  PlayItem item,
  DownloadStatus status, {
  int size = 1000,
  int received = 0,
  String? error,
}) => Download(
  item: item,
  size: size,
  received: received,
  status: status,
  error: error,
  addedAt: DateTime.utc(2026),
);

Future<FakeDownloads> pumpButton(
  WidgetTester tester, {
  Download? state,
  PlayItem? item = movie,
  bool tv = false,
  bool compact = false,
}) async {
  final fake = FakeDownloads({?state?.key: ?state});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        downloadsProvider.overrideWith(() => fake),
        televisionProvider.overrideWithValue(tv),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: DownloadButton(item: item, compact: compact),
          ),
        ),
      ),
    ),
  );
  return fake;
}

void main() {
  testWidgets('rien de téléchargé : « Télécharger » met le film en file', (
    tester,
  ) async {
    final fake = await pumpButton(tester);
    await tester.tap(find.text('Télécharger'));
    expect(fake.calls, ['add movie:1']);
  });

  testWidgets('fichier inconnu : bouton désactivé', (tester) async {
    final fake = await pumpButton(tester, item: null);
    final button = tester.widget<ButtonStyleButton>(
      find.bySubtype<ButtonStyleButton>(),
    );
    expect(button.onPressed, isNull);
    expect(fake.calls, isEmpty);
  });

  testWidgets('en attente : appui = pause', (tester) async {
    final fake = await pumpButton(
      tester,
      state: download(movie, DownloadStatus.queued),
    );
    expect(find.text('En attente'), findsOneWidget);
    await tester.tap(find.text('En attente'));
    expect(fake.calls, ['pause movie:1']);
  });

  testWidgets('en cours : avancement en %, appui = pause', (tester) async {
    final fake = await pumpButton(
      tester,
      state: download(movie, DownloadStatus.running, received: 340),
    );
    expect(find.text('34 %'), findsOneWidget);
    await tester.tap(find.text('34 %'));
    expect(fake.calls, ['pause movie:1']);
  });

  testWidgets('en pause : appui = reprise', (tester) async {
    final fake = await pumpButton(
      tester,
      state: download(movie, DownloadStatus.paused, received: 500),
    );
    expect(find.text('En pause · 50 %'), findsOneWidget);
    await tester.tap(find.text('En pause · 50 %'));
    expect(fake.calls, ['resume movie:1']);
  });

  testWidgets('téléchargé : suppression seulement après confirmation', (
    tester,
  ) async {
    final fake = await pumpButton(
      tester,
      state: download(movie, DownloadStatus.ready, received: 1000),
    );
    await tester.tap(find.text('Téléchargé'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer la vidéo ?'), findsOneWidget);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);

    await tester.tap(find.text('Téléchargé'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['remove movie:1']);
  });

  testWidgets('en échec : la raison et « Réessayer »', (tester) async {
    final fake = await pumpButton(
      tester,
      state: download(
        movie,
        DownloadStatus.failed,
        error: 'Espace disque insuffisant',
      ),
    );
    expect(find.text('Espace disque insuffisant'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    expect(fake.calls, ['resume movie:1']);
  });

  testWidgets('variante compacte : icône, libellé en infobulle', (
    tester,
  ) async {
    final fake = await pumpButton(tester, compact: true);
    expect(find.text('Télécharger'), findsNothing);
    await tester.tap(find.byTooltip('Télécharger'));
    expect(fake.calls, ['add movie:1']);
  });

  testWidgets('Android TV : aucun bouton', (tester) async {
    await pumpButton(tester, tv: true);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.text('Télécharger'), findsNothing);
  });

  testWidgets('Entrée active le bouton qui a le focus', (tester) async {
    final fake = await pumpButton(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fake.calls, ['add movie:1']);
  });
}
