import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../logging.dart';

/// Focus audio d'Android (`MainActivity.kt`, D-071) : demandé à chaque
/// passage en lecture, rendu à la fermeture du lecteur. Une autre app qui
/// prend le son (appel, vidéo, assistant), ou un casque débranché, met en
/// pause, sans reprise automatique : l'utilisateur relance lui-même. Une
/// notification courte ne fait rien (le système baisse le volume). Hors
/// Android, sans effet.
final class AudioFocus {
  AudioFocus({
    required Stream<bool> playing,
    required this._pause,
    bool? android,
  }) : _android = android ?? Platform.isAndroid {
    if (!_android) return;
    _channel.setMethodCallHandler(_onCall);
    _playing = playing.listen((playing) {
      if (playing && !_held) unawaited(_request());
    });
  }

  static const _channel = MethodChannel('couchplay/audio');

  final Future<void> Function() _pause;
  final bool _android;
  StreamSubscription<bool>? _playing;

  /// Focus tenu : une reprise de la même lecture ne le redemande pas.
  var _held = false;
  var _disposed = false;

  Future<void> _request() async {
    _held = true;
    final granted = await _invoke<bool>('request') ?? true;
    if (!granted && !_disposed) await _interrupted('focus');
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'interrupted' && !_disposed) {
      await _interrupted(call.arguments as String?);
    }
  }

  /// Le natif a déjà rendu le focus : redemandé à la prochaine lecture.
  Future<void> _interrupted(String? reason) async {
    _held = false;
    log(
      reason == 'noisy'
          ? 'Lecture : pause, casque débranché'
          : 'Lecture : pause, son pris par une autre app',
    );
    await _pause();
  }

  Future<T?> _invoke<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      // Ancienne activité sans ce canal : lecture sans focus, comme avant.
    } on PlatformException catch (e) {
      log('Focus audio', error: e.message);
    }
    return null;
  }

  Future<void> dispose() async {
    if (!_android || _disposed) return;
    _disposed = true;
    await _playing?.cancel();
    // ponytail: un seul lecteur ouvert à la fois ; deux écrans de lecteur
    // empilés se prendraient le canal.
    _channel.setMethodCallHandler(null);
    await _invoke<void>('abandon');
  }
}
