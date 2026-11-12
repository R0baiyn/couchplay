import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../settings/app_settings.dart';

/// Piste réellement lue : celle choisie, sinon (choix automatique) la piste
/// par défaut du flux, sinon la première. `state.track` ne porte les codecs
/// que pour un choix de l'utilisateur ; ceux du flux sont dans `state.tracks`.
T? _active<T>(
  List<T> tracks,
  String selectedId,
  String Function(T) id,
  bool? Function(T) isDefault,
) {
  final real = tracks.where((t) => id(t) != 'auto' && id(t) != 'no').toList();
  if (real.isEmpty) return null;
  return real.where((t) => id(t) == selectedId).firstOrNull ??
      real.where((t) => isDefault(t) ?? false).firstOrNull ??
      real.first;
}

String? _bitrate(num? bitsPerSecond) {
  if (bitsPerSecond == null || bitsPerSecond <= 0) return null;
  if (bitsPerSecond >= 1e6) {
    return '${(bitsPerSecond / 1e6).toStringAsFixed(1).replaceAll('.', ',')}'
        ' Mb/s';
  }
  return '${(bitsPerSecond / 1e3).round()} kb/s';
}

String? _nonEmpty(String? text) => text == null || text.isEmpty ? null : text;

/// Infos techniques du flux en cours, une ligne pour l'image et une pour le
/// son. Une info inconnue (0, absente) est omise ; une ligne vide aussi.
List<String> techInfo(PlayerState state) {
  final video = _active(
    state.tracks.video,
    state.track.video.id,
    (t) => t.id,
    (t) => t.isDefault,
  );
  final audio = _active(
    state.tracks.audio,
    state.track.audio.id,
    (t) => t.id,
    (t) => t.isDefault,
  );
  final (w, h) = (state.width ?? 0, state.height ?? 0);
  final videoLine = [
    if (w > 0 && h > 0) '$w × $h',
    _nonEmpty(video?.codec),
    _bitrate(video?.bitrate),
  ].nonNulls.join(' · ');
  final audioLine = [
    _nonEmpty(audio?.codec),
    _nonEmpty(state.audioParams.hrChannels) ?? _nonEmpty(audio?.channels),
    _bitrate(state.audioBitrate ?? audio?.bitrate),
  ].nonNulls.join(' · ');
  return [
    if (videoLine.isNotEmpty) videoLine,
    if (audioLine.isNotEmpty) audioLine,
  ];
}

/// Encart d'infos techniques du lecteur, seulement si le mode debug est
/// coché. Du texte seul : il ne prend pas le focus.
class TechInfo extends ConsumerWidget {
  const TechInfo({super.key, required this.player});

  final Player player;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(appSettingsProvider.select((s) => s.debug))
      ? _TechInfoText(player: player)
      : const SizedBox.shrink();
}

class _TechInfoText extends StatefulWidget {
  const _TechInfoText({required this.player});

  final Player player;

  @override
  State<_TechInfoText> createState() => _TechInfoTextState();
}

class _TechInfoTextState extends State<_TechInfoText> {
  final _subscriptions = <StreamSubscription<Object?>>[];
  late List<String> _lines = techInfo(widget.player.state);

  @override
  void initState() {
    super.initState();
    final s = widget.player.stream;
    for (final stream in <Stream<Object?>>[
      s.width,
      s.height,
      s.tracks,
      s.track,
      s.audioParams,
      s.audioBitrate,
    ]) {
      _subscriptions.add(stream.listen((_) => _refresh()));
    }
  }

  // Ces flux émettent souvent : on ne reconstruit que si le texte change.
  void _refresh() {
    final lines = techInfo(widget.player.state);
    if (lines.join('\n') != _lines.join('\n')) setState(() => _lines = lines);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        _lines.join('\n'),
        textAlign: TextAlign.end,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}
