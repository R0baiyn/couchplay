import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_files.dart';
import '../server/json_read.dart';

/// Réglages globaux de l'app (pas par compte), gardés dans `settings.json`
/// à la racine du dossier de support : ils survivent à la suppression d'un
/// compte. Les prochains réglages globaux s'ajoutent ici.
final class AppSettings {
  const AppSettings({
    this.debug = false,
    this.wifiOnly = true,
    this.deleteWatched = false,
  });

  /// Mode debug : le lecteur affiche les infos techniques du flux.
  final bool debug;

  /// Télécharger en Wi-Fi seulement (D-037) : sur réseau mobile, la file des
  /// téléchargements attend. Activé par défaut, pour ne pas vider un forfait
  /// par surprise.
  final bool wifiOnly;

  /// Effacer une fois vu (D-037) : la vidéo téléchargée d'un contenu qui
  /// passe à « vu » est supprimée, à la sortie du lecteur. Désactivé par
  /// défaut.
  final bool deleteWatched;

  factory AppSettings.fromJson(Object? json) {
    final map = asMap(json);
    return AppSettings(
      debug: asBool(map['debug']) ?? false,
      wifiOnly: asBool(map['wifiOnly']) ?? true,
      deleteWatched: asBool(map['deleteWatched']) ?? false,
    );
  }

  Map<String, Object?> toJson() => {
    'debug': debug,
    'wifiOnly': wifiOnly,
    'deleteWatched': deleteWatched,
  };

  AppSettings copyWith({bool? debug, bool? wifiOnly, bool? deleteWatched}) =>
      AppSettings(
        debug: debug ?? this.debug,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        deleteWatched: deleteWatched ?? this.deleteWatched,
      );
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

  Future<void> setDebug(bool debug) => _set(state.copyWith(debug: debug));

  Future<void> setWifiOnly(bool wifiOnly) =>
      _set(state.copyWith(wifiOnly: wifiOnly));

  Future<void> setDeleteWatched(bool deleteWatched) =>
      _set(state.copyWith(deleteWatched: deleteWatched));

  Future<void> _set(AppSettings settings) {
    state = settings;
    final file = ref.read(appSettingsFileProvider);
    if (file == null) return Future.value();
    return _writer.write(file, jsonEncode(state.toJson()));
  }
}
