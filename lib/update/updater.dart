import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging.dart';
import 'hidden_process.dart';

/// Une version publiée plus récente que celle de l'app, et le fichier à
/// télécharger pour cette variante (installée ou portable).
final class Update {
  const Update({
    required this.version,
    required this.notes,
    required this.asset,
    required this.size,
    required this.portable,
  });

  /// Sans le `v` du tag : `0.1.1`.
  final String version;

  /// Notes de version, en texte brut (message du tag).
  final String notes;
  final Uri asset;

  /// Taille annoncée par GitHub, en octets : un téléchargement d'une autre
  /// taille est refusé.
  final int size;

  /// Zip portable, sinon installateur.
  final bool portable;
}

/// Numéros d'une version : `v0.1.10+3` donne `[0, 1, 10]`. `null` si le
/// texte n'est pas une version.
List<int>? parseVersion(String text) {
  final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$')
      .firstMatch(text.trim());
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match[i]!)];
}

/// [candidate] est strictement plus récente que [current].
bool isNewer(String candidate, String current) {
  final a = parseVersion(candidate);
  final b = parseVersion(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// Hôtes d'où les fichiers d'une release sont téléchargés : la page GitHub,
/// puis le stockage vers lequel elle redirige.
const downloadHosts = {
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

bool isAllowedDownload(Uri url) =>
    url.scheme == 'https' && downloadHosts.contains(url.host);

/// La mise à jour proposée par une réponse de `releases/latest`, si elle est
/// plus récente que [current] et contient le fichier de cette variante.
Update? updateFrom(
  Object? json, {
  required String current,
  required bool portable,
}) {
  if (json is! Map) return null;
  final tag = json['tag_name'];
  if (tag is! String || !isNewer(tag, current)) return null;
  final suffix = portable ? '-windows-portable.zip' : '-windows-setup.exe';
  final assets = json['assets'];
  for (final asset in assets is List ? assets : const []) {
    if (asset is! Map) continue;
    final (name, link, size) = (
      asset['name'],
      asset['browser_download_url'],
      asset['size'],
    );
    if (name is! String || !name.endsWith(suffix)) continue;
    final url = link is String ? Uri.tryParse(link) : null;
    if (url == null || !isAllowedDownload(url) || size is! int) continue;
    final notes = json['body'];
    return Update(
      version: tag.replaceFirst(RegExp('^v'), ''),
      notes: notes is String ? notes.trim() : '',
      asset: url,
      size: size,
      portable: portable,
    );
  }
  return null;
}

/// Vérifie les GitHub Releases du dépôt public (sans jeton) et installe une
/// mise à jour.
///
/// L'installation se fait toujours après la fermeture de l'app : un script,
/// lancé détaché, attend la fin du processus, lance
/// l'installateur en silencieux ou copie le zip extrait par-dessus le
/// dossier de l'app, puis relance l'app si on le lui a demandé.
final class Updater {
  Updater({
    required this.version,
    required this.portable,
    required this.appDir,
    Directory? workDir,
    HttpClientAdapter? adapter,
  }) : workDir =
           workDir ??
           Directory('${Directory.systemTemp.path}\\couchplay-update'),
       _dio = Dio(
         BaseOptions(
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 30),
           headers: {'User-Agent': 'couchplay'},
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  /// Pour l'app dont l'exe est dans [appDir], d'après ce qu'il y a à côté :
  /// le marqueur `portable` du zip, ou le désinstalleur d'Inno Setup de
  /// l'installation. Ni l'un ni l'autre (un build local, une copie) : `null`,
  /// pas de mise à jour, qui installerait la version publiée ailleurs puis
  /// relancerait cette copie inchangée.
  static Updater? forApp({required String version, required Directory appDir}) {
    bool has(String name) => File('${appDir.path}\\$name').existsSync();
    final portable = has('portable');
    if (!portable && !has('unins000.exe')) return null;
    return Updater(version: version, portable: portable, appDir: appDir);
  }

  static final latest = Uri.https(
    'api.github.com',
    '/repos/R0baiyn/couchplay/releases/latest',
  );

  /// Version de l'app en cours.
  final String version;

  /// Zip portable (fichier `portable` à côté de l'exe), sinon installation.
  final bool portable;

  /// Dossier de l'exe, remplacé par la version portable.
  final Directory appDir;

  /// Téléchargement et script : vidé à chaque nouvelle préparation. Chemins
  /// avec `\` : le script les passe à `robocopy`, qui lit `/` comme une
  /// option.
  final Directory workDir;

  final Dio _dio;

  /// Avancement du téléchargement en cours, de 0 à 1.
  final progress = ValueNotifier<double>(0);

  /// La mise à jour publiée, si elle est plus récente. Lève une exception
  /// si GitHub ne répond pas.
  Future<Update?> check() async {
    final response = await _dio.getUri<Object?>(
      latest,
      options: Options(
        headers: {'Accept': 'application/vnd.github+json'},
        responseType: ResponseType.json,
      ),
    );
    return updateFrom(response.data, current: version, portable: portable);
  }

  // Une préparation par version : « Plus tard » puis « Mettre à jour »
  // n'installe pas deux fois. Un échec se retente au prochain appel.
  final _prepared = <String, Future<Directory>>{};

  /// Télécharge [update] et lance le script qui l'installera à la fermeture
  /// de l'app, sans la relancer.
  Future<Directory> prepare(Update update) =>
      _prepared[update.version] ??= _prepare(update)
        ..then<void>(
          (_) {},
          // Accolades : rendre le futur retiré relancerait son erreur.
          onError: (Object _) {
            _prepared.remove(update.version);
          },
        );

  /// Prépare [update] si ce n'est pas fait, demande la relance au script,
  /// puis ferme l'app : l'installation commence aussitôt.
  Future<void> installNow(Update update) async {
    await prepare(update);
    await _file('relaunch').create();
    exit(0);
  }

  /// Noms fixes : rien de la réponse de GitHub n'arrive dans un chemin.
  File _file(String name) => File('${workDir.path}\\$name');

  Future<Directory> _prepare(Update update) async {
    if (await workDir.exists()) await workDir.delete(recursive: true);
    await workDir.create(recursive: true);
    final package = _file(update.portable ? 'update.zip' : 'update.exe');
    await _download(update, package);
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
    log('Mise à jour ${update.version} prête, installée à la fermeture');
    return workDir;
  }

  /// Suit les redirections à la main : chaque étape doit rester en HTTPS
  /// chez GitHub.
  Future<void> _download(Update update, File file) async {
    progress.value = 0;
    var url = update.asset;
    for (var hop = 0; ; hop++) {
      if (hop > 5 || !isAllowedDownload(url)) {
        throw HttpException('Téléchargement refusé : ${url.host}');
      }
      final response = await _dio.downloadUri(
        url,
        file.path,
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
        ),
        onReceiveProgress: (received, _) =>
            progress.value = (received / update.size).clamp(0, 1),
      );
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (response.statusCode case final status? when status >= 300) {
        if (location == null) throw HttpException('Redirection sans adresse');
        url = url.resolve(location);
        continue;
      }
      final length = await file.length();
      if (length != update.size) {
        throw HttpException(
          'Taille inattendue : $length au lieu de ${update.size}',
        );
      }
      return;
    }
  }
}

/// Script d'installation, en `.cmd`, sans dépendre de la politique
/// d'exécution de PowerShell. Ses outils sont fournis avec Windows 10 et 11,
/// et appelés par leur chemin : un autre `find` ou `tar` dans le PATH (celui
/// de Git, par exemple) n'est jamais pris.
///
/// Arguments : PID de l'app, paquet (`.zip` ou `.exe`), dossier de l'app,
/// exe à relancer, fichier qui demande la relance. Avec relance,
/// l'installateur montre sa progression (`/SILENT`) : l'utilisateur voit que
/// ça avance. À la fin, seul un dossier nommé `couchplay-update` est effacé.
const installScript = r'''
@echo off
setlocal
set "bin=%SystemRoot%\System32"
:wait
"%bin%\tasklist.exe" /fi "PID eq %~1" /nh > "%~dp2pid.txt"
"%bin%\find.exe" " %~1 " "%~dp2pid.txt" >nul && ("%bin%\ping.exe" -n 2 127.0.0.1 >nul & goto wait)
if /i "%~x2"==".zip" (
  mkdir "%~dp2files"
  "%bin%\tar.exe" -xf "%~2" -C "%~dp2files" || goto clean
  "%bin%\robocopy.exe" "%~dp2files" "%~3" /e /r:5 /w:1 >nul
) else if exist "%~5" (
  start "" /wait "%~2" /SILENT /SUPPRESSMSGBOXES /NORESTART
) else (
  start "" /wait "%~2" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
)
if exist "%~5" start "" "%~4"
:clean
for %%d in ("%~dp2.") do if /i "%%~nxd"=="couchplay-update" rd /s /q "%%~fd"
''';

/// Version de l'app (`pubspec.yaml`), fournie par `main()`.
final appVersionProvider = Provider<String>(
  (ref) => throw UnimplementedError('appVersionProvider doit être surchargé'),
);

/// Absent hors de Windows et en debug : `main()` le fournit pour une
/// version release sous Windows.
final updaterProvider = Provider<Updater?>((ref) => null);

/// Vérification au démarrage. Une erreur réseau ou GitHub donne `null` :
/// l'app continue sans mise à jour.
final startupUpdateProvider = FutureProvider<Update?>((ref) async {
  final updater = ref.watch(updaterProvider);
  if (updater == null) return null;
  try {
    return await updater.check();
  } on Exception catch (e) {
    log('Vérification des mises à jour', error: e.runtimeType);
    return null;
  }
});
