import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/account_files.dart';
import '../server/json_read.dart';

/// Réglages globaux de l'app (pas par compte), gardés dans `settings.json`
/// à la racine du dossier de support : ils survivent à la suppression d'un
/// compte. Les prochains réglages globaux s'ajoutent ici.
final class AppSettings {
  const AppSettings({this.debug = false});

  /// Mode debug : le lecteur affiche les infos techniques du flux.
  final bool debug;

  factory AppSettings.fromJson(Object? json) =>
      AppSettings(debug: asBool(asMap(json)['debug']) ?? false);

  Map<String, Object?> toJson() => {'debug': debug};
}

/// Le fichier des réglages, injecté par `main()`. `null` (tests) : réglages
/// par défaut, rien n'est écrit.
final appSettingsFileProvider = Provider<File?>((ref) => null);

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

final class AppSettingsNotifier extends Notifier<AppSettings> {
  final _writer = SerialFileWriter(failure: 'Réglages non écrits');

  @override
  AppSettings build() {
    final file = ref.watch(appSettingsFileProvider);
    if (file == null) return const AppSettings();
    // Lecture synchrone : quelques octets, lus une fois au démarrage.
    try {
      return AppSettings.fromJson(jsonDecode(file.readAsStringSync()));
    } on FileSystemException {
      return const AppSettings();
    } on FormatException {
      return const AppSettings();
    }
  }

  Future<void> setDebug(bool debug) {
    state = AppSettings(debug: debug);
    final file = ref.read(appSettingsFileProvider);
    if (file == null) return Future.value();
    return _writer.write(file, jsonEncode(state.toJson()));
  }
}
