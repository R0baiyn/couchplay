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

final _queryCredentials = RegExp(
  r'''((?:[?&]|\\u0026)(?:username|password)=)[^&#\s"']*''',
  caseSensitive: false,
);
final _userInfo = RegExp(
  r'''(\b[a-z][a-z0-9+.-]*://)[^/\s:@"']+:[^/\s@"']+@''',
  caseSensitive: false,
);
final _streamPath = RegExp(
  '(/(?:movie|series|live|timeshift)/)$_segment/$_segment(?=/)',
);
// Réponse JSON du serveur : "username":"…", valeur échappée, nombre ou
// chaîne coupée par un aperçu tronqué.
final _jsonCredentials = RegExp(
  r'''("(?:username|password)"\s*:\s*)(?:"(?:[^"\\]|\\.)*"?|[^,}\]\s]+)''',
  caseSensitive: false,
);
// Direct sans préfixe : http://hôte:port/U/P/42 ou /42.ts
final _shortLivePath = RegExp(
  '(://$_segment/)$_segment/$_segment'
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
      .replaceAllMapped(_shortLivePath, (m) => '${m[1]}$_mask/$_mask');

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
  _journal?.add(text);
}

const _stackLines = 12;
const _maxEntry = 4000;

/// Ligne d'en-tête du journal, écrite à chaque démarrage.
String startLine({required String version, required bool television}) =>
    'Démarrage : CouchPlay $version, ${Platform.operatingSystem} '
    '${Platform.operatingSystemVersion}, ${Abi.current()}'
    '${television ? ', TV' : ''}';

_Journal? _journal;

/// Fichier du journal ouvert, `null` sans journal (tests, outils).
File? get journalFile => _journal?.file;

/// Ouvre le journal [file] : [log] y écrit désormais, en tâche de fond. Au
/// delà de [maxBytes], le fichier devient `<file>.1` (l'ancien est écrasé).
/// Ne touche pas au disque tout de suite : un fichier impossible à écrire
/// coupe seulement le journal.
void openJournal(File file, {int maxBytes = 1 << 20}) {
  _journal = _Journal(file, maxBytes);
}

/// Attend que les lignes déjà journalisées soient écrites, [timeout] au plus :
/// avant de quitter l'app sans passer par sa fermeture normale.
Future<void> flushJournal({
  Duration timeout = const Duration(seconds: 2),
}) async {
  await _journal?._pending.timeout(timeout, onTimeout: () {});
}

/// Vide puis ferme le journal : [log] n'écrit plus dans aucun fichier.
Future<void> closeJournal() async {
  await flushJournal();
  _journal = null;
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
  _Journal(this.file, this.maxBytes);

  final File file;
  final int maxBytes;

  final _buffer = StringBuffer();
  Future<void> _pending = Future.value();
  var _queued = false;
  var _broken = false;
  int? _size;

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
    if (_repeats > 0) {
      _buffer.writeln('${_now()} (entrée précédente répétée $_repeats fois)');
      _repeats = 0;
    }
    _last = text;
    _buffer.writeln('${_now()} $text');
    if (_queued) return;
    _queued = true;
    _pending = _pending.then((_) => _write());
  }

  static String _now() => DateTime.now().toIso8601String().substring(0, 23);

  Future<void> _write() async {
    _queued = false;
    final bytes = utf8.encode(_buffer.toString());
    _buffer.clear();
    if (_broken) return;
    try {
      var size = _size ??= await file.exists() ? await file.length() : 0;
      if (size > 0 && size + bytes.length > maxBytes) {
        final old = File('${file.path}.1');
        if (await old.exists()) await old.delete();
        await file.rename(old.path);
        size = 0;
      }
      await file.writeAsBytes(bytes, mode: FileMode.append);
      _size = size + bytes.length;
    } on FileSystemException {
      _broken = true;
    }
  }
}
