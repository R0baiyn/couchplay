import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// Écran temporaire de l'étape 0 : vérifie que media_kit lit un flux public sur
// Windows et Android. Supprimé à la tâche 4.1, avec l'URL de test.
const _testStreamUrl = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';

class PlayerTestScreen extends StatefulWidget {
  const PlayerTestScreen({super.key});

  @override
  State<PlayerTestScreen> createState() => _PlayerTestScreenState();
}

class _PlayerTestScreenState extends State<PlayerTestScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    _player.open(Media(_testStreamUrl));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Video(controller: _controller),
    );
  }
}
