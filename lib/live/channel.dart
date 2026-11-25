import 'dart:convert';

import '../server/json_read.dart';

/// Une chaîne du direct, telle que `get_live_streams` la décrit.
///
/// Les catégories du direct ont le même format que celles des films :
/// `Category` et `parseCategories` de `server/models.dart` servent tels quels.
final class Channel {
  const Channel({
    required this.id,
    required this.name,
    this.number,
    this.logo,
    this.epgChannelId,
    this.categoryId,
  });

  /// `stream_id`, en texte comme les autres ids.
  final String id;
  final String name;

  /// `num` : ordre d'affichage voulu par le serveur.
  final int? number;

  /// Adresse http(s) du logo ; souvent absente.
  final String? logo;

  /// Lien avec le guide des programmes (`channel@id` du XML) ; souvent absent.
  final String? epgChannelId;
  final String? categoryId;
}

/// Chaînes d'une réponse de `get_live_streams`, triées par `num` (tri stable,
/// sans `num` à la fin). Fonction de premier niveau : appelée dans un isolate,
/// la liste fait plusieurs Mo.
List<Channel> parseChannels(String text) {
  return sortedByNumber([
    for (final entry in asList(jsonDecode(text))) ?_channel(asMap(entry)),
  ]);
}

/// [channels] triées par `num`, sans `num` à la fin, l'ordre de départ gardé
/// entre égales.
List<Channel> sortedByNumber(List<Channel> channels) {
  // `List.sort` n'est pas stable : l'index départage les égalités.
  final indexed = channels.indexed.toList()
    ..sort((a, b) {
      final byNumber = _compareNumbers(a.$2.number, b.$2.number);
      return byNumber != 0 ? byNumber : a.$1.compareTo(b.$1);
    });
  return [for (final (_, channel) in indexed) channel];
}

int _compareNumbers(int? a, int? b) => switch ((a, b)) {
  (null, null) => 0,
  (null, _) => 1,
  (_, null) => -1,
  (final int a, final int b) => a.compareTo(b),
};

Channel? _channel(Map<String, Object?> map) {
  // Les radios (`radio_streams`) ne sont pas des chaînes de télévision. Tout
  // autre type est gardé : selon le serveur, une chaîne peut être `live`,
  // `created_live` ou sans `stream_type`.
  if (asString(map['stream_type'])?.trim() == 'radio_streams') return null;
  final id = asId(map['stream_id']);
  final name = asString(map['name'])?.trim();
  if (id == null || name == null) return null;
  return Channel(
    id: id,
    name: name,
    number: asInt(map['num']),
    logo: asUrl(map['stream_icon']),
    epgChannelId: asId(map['epg_channel_id']),
    categoryId: asId(map['category_id']),
  );
}
