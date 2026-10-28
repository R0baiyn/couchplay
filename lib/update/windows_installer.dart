import 'dart:convert';
import 'dart:io';

import 'updater.dart';
import 'hidden_process.dart';

/// Installation sous Windows, toujours après la fermeture de l'app : un
/// script, lancé détaché, attend la fin du processus, lance l'installateur
/// en silencieux ou copie le zip extrait par-dessus le dossier de l'app,
/// puis relance l'app si on le lui a demandé.
final class WindowsInstaller implements Installer {
  WindowsInstaller({
    required this.portable,
    required this.appDir,
    Directory? workDir,
  }) : workDir =
           workDir ??
           Directory('${Directory.systemTemp.path}\\couchplay-update');

  /// Pour l'app dont l'exe est dans [appDir], d'après ce qu'il y a à côté :
  /// le marqueur `portable` du zip, ou le désinstalleur d'Inno Setup de
  /// l'installation. Ni l'un ni l'autre (un build local, une copie) : `null`,
  /// pas de mise à jour, qui installerait la version publiée ailleurs puis
  /// relancerait cette copie inchangée.
  static WindowsInstaller? forApp(Directory appDir) {
    bool has(String name) => File('${appDir.path}\\$name').existsSync();
    final portable = has('portable');
    if (!portable && !has('unins000.exe')) return null;
    return WindowsInstaller(portable: portable, appDir: appDir);
  }

  /// Zip portable (fichier `portable` à côté de l'exe), sinon installation.
  final bool portable;

  /// Dossier de l'exe, remplacé par la version portable.
  final Directory appDir;

  /// Téléchargement et script. Chemins avec `\` : le script les passe à
  /// `robocopy`, qui lit `/` comme une option.
  @override
  final Directory workDir;

  @override
  String get assetSuffix =>
      portable ? '-windows-portable.zip' : '-windows-setup.exe';

  @override
  String get later => 'à la fermeture de CouchPlay';

  @override
  String get packageName => portable ? 'update.zip' : 'update.exe';

  File _file(String name) => File('${workDir.path}\\$name');

  /// Lance le script, qui attend la fermeture de l'app.
  @override
  Future<void> prepared(Update update, File package) async {
    final script = _file('install.cmd');
    // Fins de ligne Windows, quelles que soient celles du fichier source.
    await script.writeAsString(LineSplitter.split(installScript).join('\r\n'));
    // Chaque chemin est un argument séparé, jamais inséré dans le texte du
    // script.
    startHiddenScript(script.path, [
      '$pid',
      package.path,
      appDir.path,
      Platform.resolvedExecutable,
      _file('relaunch').path,
    ]);
  }

  /// Demande la relance au script, puis ferme l'app : l'installation
  /// commence aussitôt.
  @override
  Future<void> installNow() async {
    await _file('relaunch').create();
    exit(0);
  }

  /// Rien à faire : le script d'une session précédente a déjà installé la
  /// mise à jour à sa fermeture.
  @override
  Future<bool> installPending(String current) async => false;
}

/// Script d'installation, en `.cmd`, sans dépendre de la politique
/// d'exécution de PowerShell. Ses outils sont fournis avec Windows 10 et 11,
/// et appelés par leur chemin : un autre `find` ou `tar` dans le PATH (celui
/// de Git, par exemple) n'est jamais pris.
///
/// Arguments : PID de l'app, paquet (`.zip` ou `.exe`), dossier de l'app,
/// exe à relancer, fichier qui demande la relance. L'app est attendue toutes
/// les 3 s : après « Plus tard », le script peut attendre des heures. Avec
/// relance, l'installateur montre sa progression (`/SILENT`) : l'utilisateur
/// voit que ça avance. L'app est relancée même si l'extraction échoue (elle
/// reste dans sa version). À la fin, seul un dossier nommé
/// `couchplay-update` est effacé.
///
/// Portable : seul `data\flutter_assets` est remis en miroir, un nom propre
/// à Flutter ; le reste est seulement recopié. Le zip a pu être extrait au
/// milieu d'autres fichiers (Bureau, Téléchargements, avec peut-être un
/// dossier `data` à soi), jamais effacés.
const installScript = r'''
@echo off
setlocal
set "bin=%SystemRoot%\System32"
:wait
"%bin%\tasklist.exe" /fi "PID eq %~1" /fi "IMAGENAME eq %~nx4" /nh > "%~dp2pid.txt"
"%bin%\find.exe" " %~1 " "%~dp2pid.txt" >nul && ("%bin%\ping.exe" -n 4 127.0.0.1 >nul & goto wait)
if /i "%~x2"==".zip" (
  mkdir "%~dp2files"
  "%bin%\tar.exe" -xf "%~2" -C "%~dp2files" || goto relaunch
  "%bin%\robocopy.exe" "%~dp2files\data\flutter_assets" "%~3\data\flutter_assets" /mir /r:5 /w:1 >nul
  "%bin%\robocopy.exe" "%~dp2files" "%~3" /e /r:5 /w:1 >nul
) else if exist "%~5" (
  start "" /wait "%~2" /SILENT /SUPPRESSMSGBOXES /NORESTART
) else (
  start "" /wait "%~2" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
)
:relaunch
if exist "%~5" start "" "%~4"
for %%d in ("%~dp2.") do if /i "%%~nxd"=="couchplay-update" rd /s /q "%%~fd"
''';
