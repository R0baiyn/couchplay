import 'package:couchplay/downloads/download.dart';
import 'package:couchplay/downloads/offline_list.dart';
import 'package:couchplay/library/library.dart';
import 'package:flutter_test/flutter_test.dart';

Download _movie(
  String id, {
  DownloadStatus status = DownloadStatus.ready,
  int size = 0,
  int received = 0,
}) => Download(
  item: PlayItem.movie(
    id: id,
    extension: 'mkv',
    name: 'Film $id',
    poster: null,
  ),
  size: size,
  received: received,
  status: status,
  addedAt: DateTime.utc(2026),
);

Download _episode(
  String id,
  int season,
  int episode, {
  String series = '5',
  DownloadStatus status = DownloadStatus.ready,
  int size = 0,
}) => Download(
  item: PlayItem.episode(
    id: id,
    extension: 'mp4',
    name: 'Série $series',
    seriesId: series,
    season: season,
    episode: episode,
  ),
  size: size,
  status: status,
  addedAt: DateTime.utc(2026),
);

void main() {
  test('liste vide : rien de partout', () {
    expect(activeDownloads(const []), isEmpty);
    expect(readyGroups(const []), isEmpty);
    expect(usedBytes(const []), 0);
    expect(runningDownload(const []), isNull);
    expect(hasWaitingDownload(const []), isFalse);
  });

  test('un film prêt seul : un groupe à sa clé, rien d\'actif', () {
    final movie = _movie('1', size: 100);
    expect(activeDownloads([movie]), isEmpty);
    expect(readyGroups([movie]), {
      movie.key: [movie],
    });
    expect(usedBytes([movie]), 100);
  });

  test('série sur deux saisons : un groupe, épisodes triés, taille totale', () {
    final s2e1 = _episode('a', 2, 1, size: 30);
    final s1e2 = _episode('b', 1, 2, size: 20);
    final s1e1 = _episode('c', 1, 1, size: 10);
    final movie = _movie('9', size: 5);
    final groups = readyGroups([s2e1, movie, s1e2, s1e1]);
    expect(groups.keys, ['5', movie.key], reason: 'ordre d\'ajout du premier');
    expect(groups['5'], [s2e1, s1e2, s1e1]);
    expect(sortedEpisodes(groups['5']!), [s1e1, s1e2, s2e1]);
    expect(totalSize(groups['5']!), 60);
  });

  test('mélange prêt, en cours, en attente, en échec', () {
    final ready = _movie('1', size: 100);
    final running = _movie(
      '2',
      status: DownloadStatus.running,
      size: 200,
      received: 50,
    );
    final queued = _movie('3', status: DownloadStatus.queued, received: 7);
    final failed = _movie('4', status: DownloadStatus.failed, received: 3);
    final all = [ready, running, queued, failed];
    final active = activeDownloads(all);
    expect(active, [running, queued, failed]);
    expect(readyGroups(all).keys, [ready.key]);
    expect(usedBytes(all), 100 + 50 + 7 + 3);
    expect(runningDownload(active), running);
    expect(hasWaitingDownload(active), isTrue);
    expect(hasWaitingDownload([failed]), isFalse);
    expect(
      hasWaitingDownload([_movie('5', status: DownloadStatus.paused)]),
      isFalse,
    );
    expect(runningDownload([queued, failed]), isNull);
  });

  test('place prise en direct : seul le reçu de plus est ajouté', () {
    final running = _movie('2', status: DownloadStatus.running, received: 50);
    expect(usedBytesLive(150, running, 80), 180);
    expect(usedBytesLive(150, running, 50), 150);
    expect(usedBytesLive(150, running, 10), 150, reason: 'jamais en arrière');
  });

  test('part reçue : bornée, inconnue sans taille', () {
    expect(receivedFraction(5, 0), isNull);
    expect(receivedFraction(25, 100), 0.25);
    expect(receivedFraction(500, 100), 1);
  });
}
