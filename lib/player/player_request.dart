import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/account_store.dart';
import '../accounts/server_session.dart';
import '../library/library.dart';
import '../server/cloudflare_dns.dart';
import '../server/models.dart';
import 'playback.dart';

/// Cloudflare ne connaît pas le nom du serveur.
final class NameNotResolved implements Exception {
  const NameNotResolved();
}

/// Flux d'un contenu sur le compte actif, ou `null` sans compte. Le nom du
/// serveur est résolu par Cloudflare, comme pour le reste de l'app ; seule
/// cette résolution peut échouer ici : [NameNotResolved].
Future<PlayRequest?> requestFor(
  WidgetRef ref,
  PlayItem item, {
  String? audioLanguage,
  String? subtitleLanguage,
  Duration? start,
}) async {
  try {
    return await _requestFor(
      ref,
      item,
      audioLanguage: audioLanguage,
      subtitleLanguage: subtitleLanguage,
      start: start,
    );
  } on Exception {
    throw const NameNotResolved();
  }
}

Future<PlayRequest?> _requestFor(
  WidgetRef ref,
  PlayItem item, {
  String? audioLanguage,
  String? subtitleLanguage,
  Duration? start,
}) async {
  final account = ref.read(activeAccountProvider);
  final client = ref.read(serverClientProvider);
  if (account == null || client == null) return null;
  final (url, headers) = await resolveForPlayer(
    client.streamUri(
      item.isEpisode ? ContentKind.series : ContentKind.movies,
      item.id,
      item.extension,
    ),
  );
  return PlayRequest(
    title: item.title,
    url: url,
    headers: headers,
    userAgent: account.userAgent,
    secrets: [account.username, account.password],
    audioLanguage: audioLanguage,
    subtitleLanguage: subtitleLanguage,
    start: start,
  );
}

/// Fichier téléchargé d'un contenu : ni serveur, ni nom à résoudre, ni
/// identifiants (D-034).
PlayRequest localRequest(
  PlayItem item,
  File file, {
  String? audioLanguage,
  String? subtitleLanguage,
  Duration? start,
}) => PlayRequest(
  title: item.title,
  url: Uri.file(file.path),
  userAgent: '',
  audioLanguage: audioLanguage,
  subtitleLanguage: subtitleLanguage,
  start: start,
);

/// Fin du fichier bien avant la fin annoncée (plus de 30 s) : le serveur a
/// coupé. Sans durée connue, on ne peut rien dire.
bool endedEarly(Duration position, Duration duration) =>
    duration > Duration.zero &&
    position < duration - const Duration(seconds: 30);
