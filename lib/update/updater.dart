import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging.dart';
import '../trusted_roots.dart';
import 'release_signature.dart';

/// Ce que l'accueil propose au démarrage, une fois devant : une mise à jour
/// publiée ([Update]) ou une mise à jour en attente que la place retient
/// ([ShortOfSpace]).
sealed class StartupOffer {}

/// Une version publiée plus récente que celle de l'app, et le fichier à
/// télécharger pour cette variante (installée, portable, APK d'une
/// architecture).
final class Update implements StartupOffer {
  const Update({
    required this.version,
    required this.notes,
    required this.asset,
    required this.size,
    this.page,
  });

  /// Sans le `v` du tag : `0.1.1`.
  final String version;

  /// Notes de version, en texte brut (message du tag).
  final String notes;
  final Uri asset;

  /// Taille annoncée par GitHub, en octets : un téléchargement d'une autre
  /// taille est refusé.
  final int size;

  /// Page de la release sur GitHub, `null` si elle n'y est pas en HTTPS :
  /// Linux l'ouvre dans le navigateur.
  final Uri? page;
}

/// Numéros d'une version : `v0.1.10+3` donne `[0, 1, 10]`. `null` si le
/// texte n'est pas une version.
List<int>? parseVersion(String text) {
  final match = _version.firstMatch(text.trim());
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match[i]!)];
}

final _version = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$');

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
const _downloadHosts = {
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

bool isAllowedDownload(Uri url) =>
    url.scheme == 'https' && _downloadHosts.contains(url.host);

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
    final page = switch (json['html_url']) {
      final String link => Uri.tryParse(link),
      _ => null,
    };
    return Update(
      version: tag.replaceFirst(RegExp('^v'), ''),
      notes: notes is String ? notes.trim() : '',
      asset: url,
      size: size,
      page: page != null && page.scheme == 'https' && page.host == 'github.com'
          ? page
          : null,
    );
  }
  return null;
}

/// Trop peu de place pour installer : [free] octets libres, environ [needed]
/// nécessaires.
final class ShortOfSpace implements StartupOffer {
  const ShortOfSpace({required this.free, required this.needed});
  final int free;
  final int needed;
}

/// Place qu'`installd` cherche à libérer sur `/data` avant d'installer
/// (`Failed to free up 1048576000`, la cible `freeCache`) : en dessous,
/// l'installation de Fire OS échoue en `INSUFFICIENT_STORAGE` (D-059, qui
/// remplace la réserve de 500 Mio de D-057, démentie par l'essai).
const _installReserve = 1048576000;

/// Place manquante pour installer un APK de [apkSize] octets, `null` si
/// [free] suffit ou est inconnue : la réserve d'`installd` plus deux APK avant
/// le téléchargement (le nôtre et la copie de l'installateur), un seul quand
/// il est déjà sur le disque ([downloaded]) (D-059).
ShortOfSpace? spaceShortfall(
  int? free,
  int apkSize, {
  required bool downloaded,
}) {
  if (free == null) return null;
  final needed = (downloaded ? 1 : 2) * apkSize + _installReserve;
  return free < needed ? ShortOfSpace(free: free, needed: needed) : null;
}

/// Ce qui change d'une plateforme à l'autre : le fichier de la release à
/// prendre, et son installation.
abstract interface class Installer {
  /// Fin du nom du fichier de cette variante : `-windows-setup.exe`…
  String get assetSuffix;

  /// Ouvre la page de la release quand l'app ne s'installe pas seule
  /// (Linux) : le dialogue ne propose que cette page, et ni [prepared] ni
  /// [installNow] ne sont appelés. `null` quand l'app s'installe seule.
  Future<void> Function(Uri page)? get openPage;

  /// Le fichier n'est confié à [prepared] que s'il figure, avec sa somme,
  /// dans la liste signée de sa release (`SHA256SUMS`, voir
  /// `release_signature.dart`).
  bool get signed;

  /// Quand s'installe une mise à jour remise à plus tard : la fin de « elle
  /// s'installera … ».
  String get later;

  /// Dossier du téléchargement, vidé avant chaque préparation.
  Directory get workDir;

  /// Nom fixe du fichier téléchargé dans [workDir] : rien de la réponse de
  /// GitHub n'arrive dans un chemin.
  String get packageName;

  /// [package], le fichier de [update], est téléchargé et vérifié : le
  /// prépare pour qu'il s'installe plus tard. [sha256] : sa somme lue dans la
  /// liste signée quand [signed], sinon `null`.
  Future<void> prepared(Update update, File package, String? sha256);

  /// Installe tout de suite la mise à jour préparée.
  Future<void> installNow();

  /// Au démarrage, installe une mise à jour préparée lors d'une session
  /// précédente, si elle est plus récente que [current] : `true` si
  /// l'installation est lancée. [allow] reçoit la taille du fichier en
  /// attente juste avant : `false` la retient, sans rien effacer.
  Future<bool> installPending(
    String current, {
    Future<bool> Function(int size)? allow,
  });

  /// Octets libres là où la mise à jour se télécharge et s'installe, `null`
  /// quand la plateforme n'en dit rien.
  Future<int?> freeSpace();
}

/// Le fichier téléchargé n'est pas dans la liste signée de sa release, ou
/// n'y a pas sa somme : il est effacé, rien ne s'installe.
final class UnsignedUpdate implements Exception {
  const UnsignedUpdate(this.name);
  final String name;

  @override
  String toString() => 'UnsignedUpdate: $name';
}

/// Vérifie les GitHub Releases du dépôt public (sans jeton), télécharge le
/// fichier de la variante de l'app, puis le confie à son [Installer].
final class Updater {
  Updater({
    required this.version,
    required this.installer,
    HttpClientAdapter? adapter,
    List<int>? publicKey,
  }) : _publicKey = publicKey ?? releaseKey,
       _dio = Dio(
         BaseOptions(
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 30),
           headers: {'User-Agent': 'couchplay'},
         ),
       ) {
    _dio.httpClientAdapter =
        adapter ??
        IOHttpClientAdapter(
          createHttpClient: () =>
              HttpClient(context: context)
                ..idleTimeout = const Duration(seconds: 3),
        );
  }

  /// Dépôt R0baiyn/couchplay désigné par son identifiant, qui ne change
  /// jamais : si le compte ou le dépôt était renommé, personne ne pourrait
  /// reprendre le nom pour publier des « mises à jour ».
  static final latest = Uri.https(
    'api.github.com',
    '/repositories/1433672657/releases/latest',
  );

  /// Contexte TLS de toutes les connexions de la mise à jour (vérification,
  /// téléchargement, liste signée) : racines du système plus celles de
  /// GitHub (`trusted_roots.dart`). Un seul, chargé au premier usage.
  static final context = trustedContext();

  /// Version de l'app en cours.
  final String version;

  final Installer installer;

  final Dio _dio;

  /// Clé de la signature des releases ; une autre seulement dans les tests.
  final List<int> _publicKey;

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

  /// Place manquante pour télécharger puis installer [update], `null` si
  /// elle suffit ou est inconnue.
  Future<ShortOfSpace?> shortfall(Update update) async => spaceShortfall(
    await installer.freeSpace(),
    update.size,
    downloaded: false,
  );

  /// Au démarrage : une mise à jour remise à plus tard s'installe d'abord
  /// ([Installer.installPending]) et rien n'est proposé ; trop peu de place,
  /// elle attend l'accord de l'utilisateur ([ShortOfSpace]), sans vérifier
  /// s'il y en a une autre. Sinon, la mise à jour publiée ([check]).
  Future<StartupOffer?> startup() async {
    ShortOfSpace? held;
    final started = await installer.installPending(
      version,
      allow: (size) async {
        held = spaceShortfall(
          await installer.freeSpace(),
          size,
          downloaded: true,
        );
        return held == null;
      },
    );
    if (started) return null;
    return held ?? await check();
  }

  Future<void> _prepare(Update update) async {
    final workDir = installer.workDir;
    if (await workDir.exists()) await workDir.delete(recursive: true);
    await workDir.create(recursive: true);
    File file(String name) =>
        File('${workDir.path}${Platform.pathSeparator}$name');
    final package = file(installer.packageName);
    String? sha256;
    if (!installer.signed) {
      await _download(update.asset, package, update.size);
    } else {
      try {
        // La liste et sa signature d'abord, à côté du fichier dans la même
        // release : une release qui n'en a pas échoue avant le gros
        // téléchargement.
        final sums = file(sumsName);
        final signature = file(signatureName);
        await _download(
          update.asset.resolve(sumsName),
          sums,
          _maxSums,
          exact: false,
        );
        await _download(
          update.asset.resolve(signatureName),
          signature,
          _maxSignature,
          exact: false,
        );
        await _download(update.asset, package, update.size);
        // Le nom porte la version annoncée : une release ne peut pas
        // resservir le fichier signé d'une version plus ancienne.
        final name = update.asset.pathSegments.last;
        sha256 = name.contains('-${update.version}-')
            ? await signedSum(
                sums: await sums.readAsBytes(),
                // Octets quelconques acceptés : le base64 décide.
                signature: String.fromCharCodes(await signature.readAsBytes()),
                name: name,
                file: package,
                publicKey: _publicKey,
              )
            : null;
        if (sha256 == null) {
          log('Mise à jour ${update.version} refusée : signature');
          throw UnsignedUpdate(name);
        }
      } on Object {
        // Refus ou erreur en route : aucun fichier non vérifié ne reste.
        if (await workDir.exists()) await workDir.delete(recursive: true);
        rethrow;
      }
    }
    await installer.prepared(update, package, sha256);
    log('Mise à jour ${update.version} prête');
  }

  /// Taille maximale de `SHA256SUMS` : quelques lignes de 100 octets.
  static const _maxSums = 64 * 1024;

  /// Taille maximale de `SHA256SUMS.sig` : 64 octets en base64.
  static const _maxSignature = 1024;

  /// Télécharge [url] dans [file], qui doit faire exactement [size] octets,
  /// ou au plus [size] si [exact] est faux (la liste et sa signature, sans
  /// avancement affiché). Suit les redirections à la main : chaque étape
  /// doit rester en HTTPS chez GitHub. Un fichier plus gros est coupé dès
  /// qu'il dépasse, sans attendre la fin.
  Future<void> _download(
    Uri url,
    File file,
    int size, {
    bool exact = true,
  }) async {
    if (exact) progress.value = 0;
    final cancel = _cancel = CancelToken();
    var tooBig = false;
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
            if (received > size) {
              tooBig = true;
              cancel.cancel();
            }
            if (exact) progress.value = (received / size).clamp(0, 1);
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
        if (tooBig) throw HttpException('Plus gros que $size octets');
        rethrow;
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (response.statusCode case final status? when status >= 300) {
        if (location == null) {
          throw const HttpException('Redirection sans adresse');
        }
        url = url.resolve(location);
        continue;
      }
      final length = await file.length();
      if (exact ? length != size : length > size) {
        throw HttpException('Taille inattendue : $length au lieu de $size');
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

/// Au démarrage : voir [Updater.startup]. Une erreur réseau ou GitHub donne
/// `null` : l'app continue sans mise à jour.
final startupUpdateProvider = FutureProvider<StartupOffer?>((ref) async {
  final updater = ref.watch(updaterProvider);
  if (updater == null) return null;
  try {
    return await updater.startup();
  } on Exception catch (e) {
    log('Vérification des mises à jour', error: '${e.runtimeType}: $e');
    return null;
  }
});
