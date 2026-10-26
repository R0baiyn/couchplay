// Lecture tolérante du JSON du serveur, mal typé : nombres en chaînes,
// booléens "1"/"0", null, liste vide à la place d'un objet vide…
// Chaque fonction renvoie null (ou une collection vide) plutôt que de lever
// une exception : une entrée invalide ne doit pas faire échouer toute la liste.

int? asInt(Object? value) => switch (value) {
  int() => value,
  double() when value.isFinite && value == value.truncateToDouble() =>
    value.toInt(),
  String() =>
    int.tryParse(value.trim()) ?? asInt(double.tryParse(value.trim())),
  _ => null,
};

double? asDouble(Object? value) => switch (value) {
  int() => value.toDouble(),
  double() when value.isFinite => value,
  String() => _parseDouble(value.trim()),
  _ => null,
};

double? _parseDouble(String text) {
  final normalized = !text.contains('.') && ','.allMatches(text).length == 1
      ? text.replaceFirst(',', '.')
      : text;
  final result = double.tryParse(normalized);
  return result != null && result.isFinite ? result : null;
}

bool? asBool(Object? value) => switch (value) {
  bool() => value,
  num() when value == 1 => true,
  num() when value == 0 => false,
  String() => switch (value.trim().toLowerCase()) {
    '1' || 'true' || 'yes' || 'on' => true,
    '0' || 'false' || 'no' || 'off' => false,
    _ => null,
  },
  _ => null,
};

/// Texte non vide, tel quel. Les nombres sont convertis (`42.0` donne `"42"`).
String? asString(Object? value) => switch (value) {
  String() when value.trim().isNotEmpty => value,
  int() => '$value',
  double() when value.isFinite =>
    value == value.truncateToDouble() ? '${value.toInt()}' : '$value',
  _ => null,
};

/// Identifiant du serveur, toujours sous forme de chaîne : il arrive tantôt en
/// nombre, tantôt en texte.
String? asId(Object? value) => asString(value)?.trim();

/// Date en secondes epoch (nombre ou texte), ou date texte ISO / `AAAA-MM-JJ hh:mm:ss`.
/// `0` signifie « pas de date ».
DateTime? asDate(Object? value) {
  final seconds = asInt(value);
  if (seconds != null) {
    return seconds > 0
        ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
        : null;
  }
  return value is String ? DateTime.tryParse(value.trim()) : null;
}

/// Liste, ou valeurs d'un objet indexé (`{"0": …, "1": …}`), sinon liste vide.
List<Object?> asList(Object? value) => switch (value) {
  List() => value,
  Map() => value.values.toList(growable: false),
  _ => const [],
};

/// Objet aux clés textuelles, sinon objet vide (le serveur envoie souvent `[]`).
Map<String, Object?> asMap(Object? value) => switch (value) {
  Map<String, Object?>() => value,
  Map() => {for (final entry in value.entries) '${entry.key}': entry.value},
  _ => const {},
};
