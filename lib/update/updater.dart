import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging.dart';

/// Une version publiée plus récente que celle de l'app, et le fichier à
/// télécharger pour cette variante (installée, portable, APK d'une
/// architecture).
final class Update {
  const Update({
    required this.version,
    required this.notes,
    required this.asset,
    required this.size,
  });

  /// Sans le `v` du tag : `0.1.1`.
  final String version;

  /// Notes de version, en texte brut (message du tag).
  final String notes;
  final Uri asset;

  /// Taille annoncée par GitHub, en octets : un téléchargement d'une autre
  /// taille est refusé.
  final int size;
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
/// plus récente que [current] et contient le fichier de cette variante, dont
/// le nom finit par [suffix].
Update? updateFrom(
  Object? json, {
  required String current,
  required String suffix,
}) {
  if (json is! Map) return null;
  final tag = json['tag_name'];
  if (tag is! String || !isNewer(tag, current)) return null;
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
    );
  }
  return null;
}

/// Ce qui change d'une plateforme à l'autre : le fichier de la release à
/// prendre, et son installation.
abstract interface class Installer {
  /// Fin du nom du fichier de cette variante : `-windows-setup.exe`…
  String get assetSuffix;

  /// Quand s'installe une mise à jour remise à plus tard : la fin de « elle
  /// s'installera … ».
  String get later;

  /// Dossier du téléchargement, vidé avant chaque préparation.
  Directory get workDir;

  /// Nom fixe du fichier téléchargé dans [workDir] : rien de la réponse de
  /// GitHub n'arrive dans un chemin.
  String get packageName;

  /// [package], le fichier de [update], est téléchargé et vérifié : le
  /// prépare pour qu'il s'installe plus tard.
  Future<void> prepared(Update update, File package);

  /// Installe tout de suite la mise à jour préparée.
  Future<void> installNow();

  /// Au démarrage, installe une mise à jour préparée lors d'une session
  /// précédente, si elle est plus récente que [current] : `true` si
  /// l'installation est lancée.
  Future<bool> installPending(String current);
}

/// Vérifie les GitHub Releases du dépôt public (sans jeton), télécharge le
/// fichier de la variante de l'app, puis le confie à son [Installer].
final class Updater {
  Updater({
    required this.version,
    required this.installer,
    HttpClientAdapter? adapter,
  }) : _dio = Dio(
         BaseOptions(
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 30),
           headers: {'User-Agent': 'couchplay'},
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  /// Dépôt R0baiyn/couchplay désigné par son identifiant, qui ne change
  /// jamais : si le compte ou le dépôt était renommé, personne ne pourrait
  /// reprendre le nom pour publier des « mises à jour ».
  static final latest = Uri.https(
    'api.github.com',
    '/repositories/1433672657/releases/latest',
  );

  /// Version de l'app en cours.
  final String version;

  final Installer installer;

  final Dio _dio;

  /// Avancement du téléchargement en cours, de 0 à 1.
  final progress = ValueNotifier<double>(0);

  CancelToken? _cancel;

  /// Arrête le téléchargement en cours : sa préparation échoue, et pourra
  /// être relancée.
  void cancel() => _cancel?.cancel();

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
    return updateFrom(
      response.data,
      current: version,
      suffix: installer.assetSuffix,
    );
  }

  // Une préparation par version : « Plus tard » puis « Mettre à jour »
  // n'installe pas deux fois. Un échec se retente au prochain appel.
  final _prepared = <String, Future<void>>{};

  /// Télécharge [update] et le prépare pour qu'il s'installe plus tard
  /// (voir [Installer.later]).
  Future<void> prepare(Update update) =>
      _prepared[update.version] ??= _prepare(update)
        ..then<void>(
          (_) {},
          // Accolades : rendre le futur retiré relancerait son erreur.
          onError: (Object _) {
            _prepared.remove(update.version);
          },
        );

  /// Prépare [update] si ce n'est pas fait, puis l'installe tout de suite.
  Future<void> installNow(Update update) async {
    await prepare(update);
    await installer.installNow();
  }

  /// Au démarrage : voir [Installer.installPending].
  Future<bool> installPending() => installer.installPending(version);

  Future<void> _prepare(Update update) async {
    final workDir = installer.workDir;
    if (await workDir.exists()) await workDir.delete(recursive: true);
    await workDir.create(recursive: true);
    final package = File(
      '${workDir.path}${Platform.pathSeparator}${installer.packageName}',
    );
    await _download(update, package);
    await installer.prepared(update, package);
    log('Mise à jour ${update.version} prête');
  }

  /// Suit les redirections à la main : chaque étape doit rester en HTTPS
  /// chez GitHub. Un fichier plus gros qu'annoncé est coupé dès qu'il
  /// dépasse, sans attendre la fin.
  Future<void> _download(Update update, File file) async {
    progress.value = 0;
    final cancel = _cancel = CancelToken();
    var tooBig = false;
    var url = update.asset;
    for (var hop = 0; ; hop++) {
      if (hop > 5 || !isAllowedDownload(url)) {
        throw HttpException('Téléchargement refusé : ${url.host}');
      }
      final Response<void> response;
      try {
        response = await _dio.downloadUri(
          url,
          file.path,
          cancelToken: cancel,
          options: Options(
            followRedirects: false,
            validateStatus: (status) => status != null && status < 400,
          ),
          onReceiveProgress: (received, _) {
            if (received > update.size) {
              tooBig = true;
              cancel.cancel();
            }
            progress.value = (received / update.size).clamp(0, 1);
          },
        );
      } on DioException catch (e) {
        // Annulé : dio rend l'erreur tout de suite, mais ferme puis efface le
        // fichier un peu après. On l'attend, pour qu'un nouvel essai puisse
        // vider le dossier.
        if (CancelToken.isCancel(e)) {
          for (var i = 0; i < 50 && await file.exists(); i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        }
        if (tooBig) throw HttpException('Plus gros que ${update.size} octets');
        rethrow;
      }
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

/// Version de l'app (`pubspec.yaml`), fournie par `main()`.
final appVersionProvider = Provider<String>(
  (ref) => throw UnimplementedError('appVersionProvider doit être surchargé'),
);

/// Absent en debug, et pour une app sans fichier publié (build local sous
/// Windows, émulateur Android) : `main()` le fournit sinon.
final updaterProvider = Provider<Updater?>((ref) => null);

/// Au démarrage : une mise à jour remise à plus tard s'installe d'abord,
/// sinon on vérifie s'il y en a une. Une erreur réseau ou GitHub donne
/// `null` : l'app continue sans mise à jour.
final startupUpdateProvider = FutureProvider<Update?>((ref) async {
  final updater = ref.watch(updaterProvider);
  if (updater == null) return null;
  try {
    if (await updater.installPending()) return null;
    return await updater.check();
  } on Exception catch (e) {
    log('Vérification des mises à jour', error: e.runtimeType);
    return null;
  }
});
