import 'package:couchplay/catalog/catalog_repository.dart';
import 'package:couchplay/live/guide.dart';
import 'package:couchplay/live/live_providers.dart';

/// Guide donné tel quel, sans serveur ni fichier :
/// `guideProvider.overrideWith(() => FixedGuide(guide))`.
final class FixedGuide extends GuideNotifier {
  FixedGuide(this.guide);

  final Guide guide;

  @override
  Future<Loaded<Guide>> build() async => Loaded(guide);

  /// « Actualiser » : rien à retélécharger.
  @override
  Future<void> refresh() async {}
}

/// Programme de [from] à [to] secondes après [origin].
Programme programmeAt(DateTime origin, int from, int to, String title) =>
    Programme(
      start: origin.add(Duration(seconds: from)),
      stop: origin.add(Duration(seconds: to)),
      title: title,
    );
