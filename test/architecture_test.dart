import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Arcs permis entre dossiers de `lib/` (D-047, D-048), « source -> cible ».
// Ne peut que rétrécir ; un arc retiré du code se retire d'ici.
const allowedArcs = <String>[
  'accounts -> server',
  'catalog -> accounts',
  'catalog -> downloads',
  'catalog -> library',
  'catalog -> player',
  'catalog -> server',
  'downloads -> accounts',
  'downloads -> library',
  'downloads -> server',
  'library -> accounts',
  'library -> server',
  'live -> accounts',
  'live -> catalog',
  'live -> library',
  'live -> player',
  'live -> server',
  'player -> accounts',
  'player -> downloads',
  'player -> library',
  'player -> server',
  'search -> catalog',
  'search -> live',
  'search -> server',
  'search -> settings',
  'settings -> accounts',
  'settings -> catalog',
  'settings -> update',
  'update -> accounts',
];

const composition = 'composition';
const shared = 'racine';
const compositionFiles = {
  'main.dart',
  'app.dart',
  'home_shell.dart',
  'home_shell_nav.dart',
};

class Arc {
  const Arc(this.source, this.target, this.where);
  final String source;
  final String target;
  final String where;
  String get key => '$source -> $target';
}

/// Nœud d'un chemin relatif à `lib/` : un dossier, `composition` ou `racine`.
String nodeOf(String path) {
  final parts = path.split('/');
  if (parts.length > 1) return parts.first;
  return compositionFiles.contains(path) ? composition : shared;
}

/// Chemin relatif à `lib/` désigné par une directive, ou null (dart:, package: tiers).
String? resolve(String from, String uri) {
  if (uri.startsWith('package:couchplay/')) {
    return uri.substring('package:couchplay/'.length);
  }
  if (uri.contains(':')) return null;
  final parts = from.split('/')..removeLast();
  for (final part in uri.split('/')) {
    if (part == '..') {
      parts.removeLast();
    } else if (part != '.') {
      parts.add(part);
    }
  }
  return parts.join('/');
}

final _directive = RegExp(
  r'''^[ \t]*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Directives d'un fichier : (URI, numéro de ligne à partir de 1).
List<(String, int)> readDirectives(String text) => [
  for (final m in _directive.allMatches(text))
    (m.group(1)!, '\n'.allMatches(text.substring(0, m.start)).length + 1),
];

/// Tous les arcs entre nœuds différents de `lib/`, hors arcs vers `racine`.
List<Arc> readArcs() {
  final arcs = <Arc>[];
  final root = Directory('lib').absolute.path.replaceAll('\\', '/');
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.absolute.path
        .replaceAll('\\', '/')
        .substring(root.length + 1);
    final text = entity.readAsStringSync();
    for (final (uri, line) in readDirectives(text)) {
      final target = resolve(path, uri);
      if (target == null) continue;
      final source = nodeOf(path);
      final dest = nodeOf(target);
      if (source == dest || dest == shared) continue;
      arcs.add(Arc(source, dest, 'lib/$path:$line'));
    }
  }
  return arcs;
}

/// Premier cycle trouvé parmi [arcs] (« a -> b -> a »), ou null : parcours
/// en profondeur, un nœud sur le chemin courant revu = cycle.
String? findCycle(List<String> arcs) {
  final next = <String, List<String>>{};
  for (final arc in arcs) {
    final [source, target] = arc.split(' -> ');
    next.putIfAbsent(source, () => []).add(target);
  }
  final done = <String>{};
  final path = <String>[];
  String? visit(String node) {
    if (path.contains(node)) {
      return [...path.sublist(path.indexOf(node)), node].join(' -> ');
    }
    if (!done.add(node)) return null;
    path.add(node);
    for (final target in next[node] ?? const <String>[]) {
      if (visit(target) case final cycle?) return cycle;
    }
    path.removeLast();
    return null;
  }

  for (final node in next.keys) {
    if (visit(node) case final cycle?) return cycle;
  }
  return null;
}

void main() {
  final arcs = readArcs();
  // Les arcs depuis `composition` sont tous permis ; ceux de la liste sont
  // entre dossiers.
  final folderArcs = arcs.where((a) => a.source != composition).toList();

  test('aucun arc hors de la liste', () {
    final extra = folderArcs
        .where((a) => !allowedArcs.contains(a.key))
        .map((a) => '${a.key} (${a.where})')
        .toList();
    expect(extra, isEmpty, reason: 'arc(s) en trop :\n${extra.join('\n')}');
  });

  test('chaque arc listé existe encore', () {
    final present = folderArcs.map((a) => a.key).toSet();
    final gone = allowedArcs.where((k) => !present.contains(k)).toList();
    expect(
      gone,
      isEmpty,
      reason: 'arc disparu : retire-le de la liste :\n${gone.join('\n')}',
    );
  });

  test('la liste est triée et sans doublon', () {
    expect(allowedArcs, ([...allowedArcs]..sort()).toSet().toList());
  });

  test('les arcs listés ne forment aucun cycle', () {
    expect(findCycle(['a -> b', 'b -> c', 'c -> a']), 'a -> b -> c -> a');
    expect(findCycle(['a -> b', 'a -> c', 'b -> c']), isNull);
    expect(findCycle(allowedArcs), isNull);
  });

  test('le numéro de ligne d\'une directive est celui de sa ligne', () {
    const text = "import 'dart:io';\n\nimport 'a.dart';\n  export 'b.dart';\n";
    expect(readDirectives(text), [
      ('dart:io', 1),
      ('a.dart', 3),
      ('b.dart', 4),
    ]);
  });

  test('racine et server n\'importent aucune fonctionnalité', () {
    final bad = folderArcs
        .where((a) => a.source == shared || a.source == 'server')
        .map((a) => '${a.key} (${a.where})')
        .toList();
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('personne n\'importe main, app ni home_shell', () {
    final bad = arcs
        .where((a) => a.target == composition)
        .map((a) => '${a.key} (${a.where})')
        .toList();
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
