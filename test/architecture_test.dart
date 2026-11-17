import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Arcs permis entre dossiers de `lib/` (D-047, D-048), « source -> cible ».
// Ne peut que rétrécir ; un arc retiré du code se retire d'ici.
const allowedArcs = <String>[
  'accounts -> catalog',
  'accounts -> downloads',
  'accounts -> server',
  'catalog -> accounts',
  'catalog -> downloads',
  'catalog -> library',
  'catalog -> player',
  'catalog -> server',
  'catalog -> settings',
  'downloads -> accounts',
  'downloads -> catalog',
  'downloads -> library',
  'downloads -> player',
  'downloads -> server',
  'downloads -> settings',
  'library -> accounts',
  'library -> catalog',
  'library -> downloads',
  'library -> player',
  'library -> server',
  'library -> settings',
  'player -> accounts',
  'player -> catalog',
  'player -> downloads',
  'player -> library',
  'player -> server',
  'player -> settings',
  'search -> catalog',
  'search -> server',
  'search -> settings',
  'settings -> accounts',
  'settings -> catalog',
  'settings -> server',
  'settings -> update',
  'update -> accounts',
];

const composition = 'composition';
const shared = 'racine';
const compositionFiles = {'main.dart', 'app.dart', 'home_shell.dart'};

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
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

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
    for (final m in _directive.allMatches(text)) {
      final target = resolve(path, m.group(1)!);
      if (target == null) continue;
      final source = nodeOf(path);
      final dest = nodeOf(target);
      if (source == dest || dest == shared) continue;
      final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
      arcs.add(Arc(source, dest, 'lib/$path:$line'));
    }
  }
  return arcs;
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
