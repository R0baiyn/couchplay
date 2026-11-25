import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/account_store.dart';
import '../accounts/server_session.dart';
import '../library/library.dart';
import '../server/cloudflare_dns.dart';
import '../server/models.dart';
import '../server/server_client.dart';
import 'playback.dart';

/// Cloudflare ne connaît pas le nom du serveur.
final class NameNotResolved implements Exception {
  const NameNotResolved();

  String get message =>
      'Serveur introuvable : Cloudflare ne connaît pas son nom.';
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
}) => streamRequest(
  ref,
  title: item.title,
  uri: (client) => client.streamUri(
    item.isEpisode ? ContentKind.series : ContentKind.movies,
    item.id,
    item.extension,
  ),
  audioLanguage: audioLanguage,
  subtitleLanguage: subtitleLanguage,
  start: start,
);

/// Comme [requestFor], pour l'adresse [uri] d'un flux du compte actif (une
/// chaîne du direct par exemple) : User-Agent, identifiants à masquer et
/// nom résolu par Cloudflare.
Future<PlayRequest?> streamRequest(
  WidgetRef ref, {
  required String title,
  required Uri Function(ServerClient client) uri,
  String? audioLanguage,
  String? subtitleLanguage,
  Duration? start,
}) async {
  try {
    return await _streamRequest(
      ref,
      title: title,
      uri: uri,
      audioLanguage: audioLanguage,
      subtitleLanguage: subtitleLanguage,
      start: start,
    );
  } on Exception {
    throw const NameNotResolved();
  }
}

Future<PlayRequest?> _streamRequest(
  WidgetRef ref, {
  required String title,
  required Uri Function(ServerClient client) uri,
  String? audioLanguage,
  String? subtitleLanguage,
  Duration? start,
}) async {
  final account = ref.read(activeAccountProvider);
  final client = ref.read(serverClientProvider);
  if (account == null || client == null) return null;
  final (url, headers) = await resolveForPlayer(uri(client));
  return PlayRequest(
    title: title,
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
