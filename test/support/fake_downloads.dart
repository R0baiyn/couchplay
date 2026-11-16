import 'dart:io';

import 'package:couchplay/downloads/download.dart';
import 'package:couchplay/downloads/downloads.dart';
import 'package:couchplay/library/library.dart';

const movie = PlayItem.movie(id: '1', extension: 'mkv', name: 'Mirage');

/// File simulée : garde les entrées données et note les appels.
final class FakeDownloads extends DownloadsNotifier {
  FakeDownloads([this.initial = const {}, this.local = const {}]);

  final Map<String, Download> initial;

  /// Clés qui « se lisent en local ».
  final Set<String> local;
  final calls = <String>[];

  /// Dossier des vidéos du compte (`null` : pas de compte).
  Directory? videos;

  @override
  Directory? get folder => videos;

  /// Fichiers des contenus prêts, par clé (`null` : fichier absent).
  final files = <String, File>{};

  @override
  File? fileOf(PlayItem item) => files[item.key];

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
