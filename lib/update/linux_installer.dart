import 'dart:io';

import 'updater.dart';

/// Ouvre une page dans le navigateur de l'utilisateur.
Future<void> _xdgOpen(Uri page) => Process.run('xdg-open', [page.toString()]);

/// Sous Linux, rien ne s'installe tout seul : l'app annonce la version (si
/// son archive est publiée) et ouvre la page de la release. Seuls
/// [assetSuffix] et [open] servent ; le reste de [Installer] n'est jamais
/// appelé.
final class LinuxInstaller implements Installer {
  /// `open` remplace `xdg-open` (tests).
  LinuxInstaller({this._open = _xdgOpen});

  final Future<void> Function(Uri page) _open;

  /// Ouvre [page], la release de la mise à jour.
  Future<void> open(Uri page) => _open(page);

  @override
  String get assetSuffix => '-linux-x64.tar.gz';

  @override
  String get later => 'jamais seule';

  @override
  Directory get workDir => Directory.systemTemp;

  @override
  String get packageName => 'couchplay.tar.gz';

  @override
  Future<void> prepared(Update update, File package) =>
      throw UnsupportedError('Pas d\'installation sous Linux');

  @override
  Future<void> installNow() =>
      throw UnsupportedError('Pas d\'installation sous Linux');

  @override
  Future<bool> installPending(String current) async => false;
}
