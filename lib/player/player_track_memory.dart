import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'tech_info.dart';

/// Langues des pistes choisies à la main, gardées pour l'épisode suivant (et
/// pour « Réessayer »). Suivies au fil de la lecture : à la fin du fichier,
/// media_kit remet la piste courante à « auto ».
class TrackMemory {
  TrackMemory(this._player) {
    _subscription = _player.stream.track.listen((track) {
      if (track.audio.language case final language?) {
        audioLanguage = language;
        _audioTitle = track.audio.title;
      }
      if (track.subtitle.id == 'no') {
        subtitleLanguage = null;
        _subtitleTitle = null;
      } else if (track.subtitle.language case final language?) {
        subtitleLanguage = language;
        _subtitleTitle = track.subtitle.title;
      }
    });
  }

  final Player _player;
  late final StreamSubscription<Track> _subscription;

  String? audioLanguage;
  String? subtitleLanguage;

  /// Noms des pistes choisies : départagent plusieurs pistes de la même
  /// langue (sous-titres complets ou seulement les passages étrangers…).
  String? _audioTitle;
  String? _subtitleTitle;

  /// mpv prend la première piste de la langue demandée. S'il y en a
  /// plusieurs, on passe à celle qui porte le même nom que la précédente.
  void matchByTitle() {
    final tracks = _player.state.tracks;
    final audio = sameTitleTrack(
      tracks.audio,
      language: audioLanguage,
      title: _audioTitle,
      languageOf: (t) => t.language,
      titleOf: (t) => t.title,
    );
    if (audio != null) unawaited(_player.setAudioTrack(audio));
    final subtitle = sameTitleTrack(
      tracks.subtitle,
      language: subtitleLanguage,
      title: _subtitleTitle,
      languageOf: (t) => t.language,
      titleOf: (t) => t.title,
    );
    if (subtitle != null) unawaited(_player.setSubtitleTrack(subtitle));
  }

  void dispose() => unawaited(_subscription.cancel());
}
