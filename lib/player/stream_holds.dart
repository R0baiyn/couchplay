import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../downloads/downloads.dart';
import 'playback.dart';

/// Ce qu'une lecture en flux doit aux téléchargements (D-036) : ils sont mis
/// en pause si le serveur refuse le flux pendant l'un d'eux, et repartent à
/// l'arrêt du flux. Le lecteur du direct passe par ici : il n'importe pas
/// `downloads` (D-084).
final class StreamHolds {
  StreamHolds(this._downloads, this._holds);

  /// À lire dans `initState` : `ref` n'est plus utilisable dans `dispose`.
  StreamHolds.read(WidgetRef ref)
    : this(
        ref.read(downloadsProvider.notifier),
        ref.read(downloadHoldsProvider.notifier),
      );

  final DownloadsNotifier _downloads;
  final DownloadHoldsNotifier _holds;

  /// Ouvre [request] sur [playback] ([openStream]) ; [opened] reçoit le
  /// ticket de chaque ouverture lancée.
  Future<void> open(
    Playback playback,
    PlayRequest request, {
    required void Function(int ticket) opened,
  }) => openStream(
    request,
    open: (request) {
      final opening = playback.open(request);
      opened(playback.ticket);
      return opening;
    },
    streaming: (open) => _holds.streaming = open,
    downloading: () => _downloads.downloading,
    pauseDownloads: () => _holds.pauseAll(DownloadHold.playback),
  );

  /// Arrête le flux de [ticket], s'il l'est encore (pas déjà arrêté, pas
  /// remplacé par un autre lecteur). Une fois fermé, le téléchargement peut
  /// repartir, sauf si un autre lecteur a ouvert un flux entre-temps.
  Future<void> stop(Playback playback, int ticket) {
    if (ticket != playback.ticket) return Future.value();
    final holds = _holds;
    final stopping = playback.stop(ticket);
    // Lu juste après l'arrêt : une ouverture plus récente le change.
    final after = playback.ticket;
    return stopping.whenComplete(() {
      if (playback.ticket == after) holds.streaming = false;
    });
  }
}
