import 'dart:collection';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

// Les URL du serveur portent les identifiants en clair : dans la query string
// (`username=<user>&password=<pass>`) et dans le chemin des flux
// (`/movie/<user>/<pass>/42.mkv`).
// Tout texte destiné aux logs passe par [redact].

const _mask = '***';
const _segment = r'''[^/\s?#"']+''';
// Identifiant dans un chemin : `Uri.encodeComponent` y laisse `'` (et
// `!*()`) ; la suite exigée après (`/…`) borne déjà la correspondance.
const _credential = r'''[^/\s?#"]+''';

final _queryCredentials = RegExp(
  r'''((?:[?&]|\\u0026)(?:username|password)=)[^&#\s"']*''',
  caseSensitive: false,
);
final _userInfo = RegExp(
  r'''(\b[a-z][a-z0-9+.-]*://)[^/\s:@"']+:[^/\s@"']+@''',
  caseSensitive: false,
);
final _streamPath = RegExp(
  '(/(?:movie|series|live|timeshift)/)$_credential/$_credential(?=/)',
);
// Réponse JSON du serveur : "username":"…", valeur échappée, nombre ou
// chaîne coupée par un aperçu tronqué.
final _jsonCredentials = RegExp(
  r'''("(?:username|password)"\s*:\s*)(?:"(?:[^"\\]|\\.)*"?|[^,}\]\s]+)''',
  caseSensitive: false,
);
// Nom de session dans un chemin (`C:\Users\<nom>`, `/home/<nom>`) : une
// erreur de fichier le recopie, et le journal se copie.
final _homePath = RegExp(
  r'''((?:[a-z]:\\users\\|/home/))[^\\/\s"']+''',
  caseSensitive: false,
);
// Direct sans préfixe : http://hôte:port/U/P/42 ou /42.ts
final _shortLivePath = RegExp(
  '(://$_segment/)$_credential/$_credential'
  r'''(?=/\d+(?:\.\w+)?(?:$|[\s?#"'/]))''',
);

/// Remplace les identifiants présents dans [text] par `***`.
///
/// [secrets] ajoute une seconde couche : ces valeurs, brutes ou encodées en URL,
/// sont masquées partout, même hors d'une URL. Les valeurs de moins de 3
/// caractères sont ignorées, sans quoi elles masqueraient tout le texte.
String redact(String text, {Iterable<String> secrets = const []}) {
  var result = text
      .replaceAllMapped(_queryCredentials, (m) => '${m[1]}$_mask')
      .replaceAllMapped(_jsonCredentials, (m) => '${m[1]}"$_mask"')
      .replaceAllMapped(_userInfo, (m) => '${m[1]}$_mask:$_mask@')
      .replaceAllMapped(_streamPath, (m) => '${m[1]}$_mask/$_mask')
      .replaceAllMapped(_shortLivePath, (m) => '${m[1]}$_mask/$_mask')
      .replaceAllMapped(_homePath, (m) => '${m[1]}$_mask');

  final variants = <String>{
    for (final secret in secrets)
      if (secret.trim().length >= 3) ...[
        secret,
        Uri.encodeComponent(secret),
        Uri.encodeQueryComponent(secret),
      ],
  }.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final variant in variants) {
    result = result.replaceAll(variant, _mask);
  }
  return result;
}

/// Écrit [message] dans le journal ([openJournal]) et, en debug seulement,
/// dans la console, identifiants masqués. [stack] : pile d'une erreur, dont
/// seules les premières lignes sont gardées.
///
/// Le journal est écrit en release aussi (D-058) : tout ce qui passe ici est
/// masqué par [redact], pile comprise, puis tronqué.
void log(
  String message, {
  Object? error,
  StackTrace? stack,
  Iterable<String> secrets = const [],
}) {
  var text = error == null ? message : '$message : $error';
  if (stack != null) {
    final lines = stack.toString().trimRight().split('\n');
    text += '\n${lines.take(_stackLines).join('\n')}';
    if (lines.length > _stackLines) text += '\n…';
  }
  // Masqué avant d'être coupé : une URL coupée au milieu ne serait plus
  // reconnue par les motifs de [redact].
  text = redact(text, secrets: secrets);
  if (text.length > _maxEntry) text = '${text.substring(0, _maxEntry)}…';
  if (kDebugMode) debugPrint('[CouchPlay] $text');
  final journal = _journal;
  if (journal != null) {
    journal.add(text);
  } else {
    _early?.add(_entry(text));
  }
}

// Chaque saut de ligne d'une entrée (message, erreur, pile) devient une ligne
// de continuation préfixée : aucune ligne du fichier ne commence par un
// horodatage qui ne vient pas de [_now] (`\r` seul compte : un éditeur y
// coupe aussi la ligne).
final _lineBreak = RegExp(r'\r\n?|\n');

String _entry(String text) =>
    '${_now()} ${text.replaceAll(_lineBreak, '\n  | ')}';

String _now() => DateTime.now().toIso8601String().substring(0, 23);

const _stackLines = 12;
const _maxEntry = 4000;

/// Ligne d'en-tête du journal, écrite à chaque démarrage.
String startLine({required String version, required bool television}) =>
    'Démarrage : CouchPlay $version, ${Platform.operatingSystem} '
    '${Platform.operatingSystemVersion}, ${Abi.current()}'
    '${television ? ', TV' : ''}';

_Journal? _journal;

/// Entrées gardées en attendant [openJournal], depuis [holdLogUntilJournal].
_Lines? _early;

/// Plafond d'un lot et des entrées gardées, en caractères : 256 Ki, soit
/// ~64 entrées pleines (4 000 caractères) et la taille que lit
/// [readJournalTail] ; au plus ~768 Kio en UTF-8, sous le plafond d'un fichier
/// (1 Mio) : un lot plein ne fait jamais déborder le fichier à lui seul.
const _maxBatch = 256 * 1024;

/// Fichier du journal ouvert, `null` sans journal (tests, outils).
File? get journalFile => _journal?.file;

/// Garde en mémoire, [maxChars] au plus, ce que [log] reçoit avant
/// [openJournal] : les erreurs du démarrage (ouverture des comptes). Rien
/// n'est écrit si le journal ne s'ouvre jamais.
void holdLogUntilJournal({int maxChars = _maxBatch}) {
  _early ??= _Lines(maxChars);
}

/// Ouvre le journal [file] : [log] y écrit désormais, en tâche de fond. Au
/// delà de [maxBytes], le fichier devient `<file>.1` (l'ancien est écrasé).
/// [header] est écrit en premier, puis les entrées gardées par
/// [holdLogUntilJournal]. Un lot qui dépasse [maxBatch] caractères perd ses
/// entrées les plus anciennes. Ne touche pas au disque tout de suite : un
/// fichier impossible à écrire coupe seulement le journal.
void openJournal(
  File file, {
  int maxBytes = 1 << 20,
  String? header,
  int maxBatch = _maxBatch,
}) {
  final journal = _journal = _Journal(file, maxBytes, maxBatch);
  if (header != null) log(header);
  final early = _early;
  _early = null;
  if (early != null) journal._takeFrom(early);
}

/// Attend que les lignes déjà journalisées soient écrites, [timeout] au plus :
/// avant de quitter l'app sans passer par sa fermeture normale.
Future<void> flushJournal({
  Duration timeout = const Duration(seconds: 2),
}) async {
  final journal = _journal;
  if (journal == null) return;
  journal._countRepeats();
  await journal._pending.timeout(timeout, onTimeout: () {});
}

/// Vide puis ferme le journal : [log] n'écrit plus dans aucun fichier, et les
/// entrées gardées par [holdLogUntilJournal] sont oubliées.
Future<void> closeJournal() async {
  await flushJournal();
  _journal = null;
  _early = null;
}

/// La fin du journal (copie `.1` puis fichier courant), [maxBytes] au plus et
/// à partir d'un début de ligne, en lignes. Vide sans journal ; un fichier
/// absent ou illisible est sauté.
Future<List<String>> readJournalTail({int maxBytes = 256 * 1024}) async {
  final file = journalFile;
  if (file == null) return const [];
  await flushJournal();
  final bytes = BytesBuilder(copy: false);
  for (final part in [File('${file.path}.1'), file]) {
    try {
      bytes.add(await part.readAsBytes());
    } on FileSystemException {
      // Pas encore de rotation, ou fichier pas encore créé.
    }
  }
  var data = bytes.takeBytes();
  if (data.length > maxBytes) {
    data = data.sublist(data.length - maxBytes);
    final newline = data.indexOf(0x0A);
    data = newline < 0 ? Uint8List(0) : data.sublist(newline + 1);
  }
  final text = utf8.decode(data, allowMalformed: true).trimRight();
  return text.isEmpty ? const [] : text.split('\n');
}

/// Lignes horodatées ajoutées à la suite du fichier, par lots, l'un après
/// l'autre et sans fichier tenu ouvert. Ne lève jamais et n'appelle jamais
/// [log] : un échec d'écriture coupe le journal en silence.
final class _Journal {
  _Journal(this.file, this.maxBytes, int maxBatch) : _batch = _Lines(maxBatch);

  final File file;
  final int maxBytes;

  /// Lot en attente d'écriture, borné : si l'écriture traîne, les entrées
  /// les plus anciennes sont abandonnées et comptées.
  final _Lines _batch;
  Future<void> _pending = Future.value();
  var _queued = false;
  var _broken = false;
  int? _size;

  /// Échecs d'écriture de suite : un échec passager (fichier verrouillé,
  /// disque plein un instant) perd seulement son lot ; le journal se coupe
  /// au 3e de suite.
  var _failures = 0;

  // Une erreur répétée à chaque image remplirait les deux fichiers en
  // quelques secondes : une entrée identique à la précédente est comptée.
  String? _last;
  var _repeats = 0;

  void add(String text) {
    if (_broken) return;
    if (text == _last) {
      _repeats++;
      return;
    }
    _countRepeats();
    _last = text;
    _queue(_entry(text));
  }

  /// Écrit le compte de l'entrée répétée : à l'entrée suivante, ou avant
  /// d'attendre le lot ([flushJournal]), sans quoi une sortie le perdrait.
  /// [_last] est gardé : la même entrée encore reste comptée.
  void _countRepeats() {
    if (_repeats == 0) return;
    _queue('${_now()} (entrée précédente répétée $_repeats fois)');
    _repeats = 0;
  }

  void _takeFrom(_Lines early) {
    early.moveTo(_batch);
    _schedule();
  }

  void _queue(String line) {
    _batch.add(line);
    _schedule();
  }

  void _schedule() {
    if (_queued || _broken) return;
    _queued = true;
    _pending = _pending.then((_) => _write());
  }

  Future<void> _write() async {
    _queued = false;
    List<int> bytes = utf8.encode(_batch.take());
    if (_broken || bytes.isEmpty) return;
    try {
      var size = _size ??= await file.exists() ? await file.length() : 0;
      if (size > 0 && size + bytes.length > maxBytes) {
        final old = File('${file.path}.1');
        if (await old.exists()) await old.delete();
        await file.rename(old.path);
        size = 0;
      }
      if (size == 0 && Platform.isLinux) {
        final failure = await _restrict();
        if (failure != null) bytes = utf8.encode('$failure\n') + bytes;
      }
      await file.writeAsBytes(bytes, mode: FileMode.append);
      _size = size + bytes.length;
      _failures = 0;
    } catch (_) {
      // Toute erreur, pas seulement d'E/S : la file ne doit jamais rester en
      // erreur, sans quoi flushJournal lèverait avant une sortie de l'app.
      // Taille relue au prochain lot : l'écriture ratée a pu en laisser une
      // partie.
      _size = null;
      _broken = ++_failures >= 3;
    }
  }

  /// Linux : le fichier, créé vide s'il manque, devient lisible par son seul
  /// propriétaire (`chmod 600`), à chaque création, rotation comprise. Rend
  /// la ligne qui dit l'échec, `null` si c'est fait.
  Future<String?> _restrict() async {
    try {
      await file.create();
      final result = await Process.run('chmod', ['600', file.path]);
      if (result.exitCode == 0) return null;
      return '${_now()} Journal : droits non restreints '
          '(chmod ${result.exitCode})';
    } on Exception catch (e) {
      return '${_now()} Journal : droits non restreints (${e.runtimeType})';
    }
  }
}

/// Lignes du journal en file, [max] caractères au plus : au-delà, les plus
/// anciennes sont abandonnées (la plus récente est toujours gardée) et
/// comptées, puis dites par une ligne en tête du texte rendu.
final class _Lines {
  _Lines(this.max);

  final int max;
  final _lines = Queue<String>();
  var _length = 0;
  var _lost = 0;

  void add(String line) {
    _lines.add(line);
    _length += line.length + 1;
    while (_length > max && _lines.length > 1) {
      _length -= _lines.removeFirst().length + 1;
      _lost++;
    }
  }

  /// Ajoute ces lignes à [other], pertes dites en tête, puis se vide.
  void moveTo(_Lines other) {
    if (_lost > 0) other.add('${_now()} ($_lost entrées perdues)');
    _lines.forEach(other.add);
    _lines.clear();
    _length = _lost = 0;
  }

  /// Le texte en attente, une ligne par entrée, puis se vide.
  String take() {
    final text = StringBuffer();
    if (_lost > 0) text.writeln('${_now()} ($_lost entrées perdues)');
    _lines.forEach(text.writeln);
    _lines.clear();
    _length = _lost = 0;
    return text.toString();
  }
}
