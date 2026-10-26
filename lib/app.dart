import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings/settings.dart';

class CouchPlayApp extends ConsumerWidget {
  const CouchPlayApp({super.key, required this.home});

  final Widget home;

  // Construits une seule fois : MaterialApp ne recalcule rien au changement de thème.
  static final _light = ThemeData(colorSchemeSeed: Colors.deepPurple);
  static final _dark = ThemeData(
    colorSchemeSeed: Colors.deepPurple,
    brightness: Brightness.dark,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(
      themePreferenceProvider.select((theme) => theme.themeMode),
    );
    return MaterialApp(
      title: 'CouchPlay',
      debugShowCheckedModeBanner: false,
      theme: _light,
      darkTheme: _dark,
      themeMode: themeMode,
      home: home,
    );
  }
}
