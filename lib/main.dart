import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'player/player_test_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const CouchPlayApp());
}

class CouchPlayApp extends StatelessWidget {
  const CouchPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CouchPlay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      home: const PlayerTestScreen(),
    );
  }
}
