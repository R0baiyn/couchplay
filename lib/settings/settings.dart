import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thème choisi dans les réglages.
enum ThemePreference {
  system(ThemeMode.system),
  light(ThemeMode.light),
  dark(ThemeMode.dark);

  const ThemePreference(this.themeMode);

  final ThemeMode themeMode;
}

/// Réglages simples et non secrets, persistés avec shared_preferences.
///
/// Le cache rend les lectures synchrones : le thème est connu dès le premier
/// rendu, sans flash de la mauvaise couleur au démarrage.
final class SettingsStore {
  SettingsStore._(this._prefs);

  static const _themeKey = 'theme';

  final SharedPreferencesWithCache _prefs;

  static Future<SettingsStore> open() async => SettingsStore._(
    await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: {_themeKey},
      ),
    ),
  );

  ThemePreference get theme {
    final name = _prefs.getString(_themeKey);
    return ThemePreference.values.asNameMap()[name] ?? ThemePreference.system;
  }

  Future<void> setTheme(ThemePreference value) =>
      _prefs.setString(_themeKey, value.name);
}

/// Ouvert dans `main()` avant le premier rendu, puis injecté via un override.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) =>
      throw UnimplementedError('settingsStoreProvider doit être surchargé'),
);

final themePreferenceProvider =
    NotifierProvider<ThemePreferenceNotifier, ThemePreference>(
      ThemePreferenceNotifier.new,
    );

final class ThemePreferenceNotifier extends Notifier<ThemePreference> {
  @override
  ThemePreference build() => ref.watch(settingsStoreProvider).theme;

  Future<void> set(ThemePreference value) async {
    state = value;
    await ref.read(settingsStoreProvider).setTheme(value);
  }
}
