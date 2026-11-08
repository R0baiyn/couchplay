/// Textes affichés pour les durées et les dates.
library;

/// `5` donne `05`.
String twoDigits(int n) => n.toString().padLeft(2, '0');

/// Position de lecture : `1:05:09`, ou `5:09` sous une heure.
String formatTime(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  final seconds = d.inSeconds % 60;
  return hours > 0
      ? '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}'
      : '$minutes:${twoDigits(seconds)}';
}

/// Durée d'un film : `1 h 05`, ou `45 min` sous une heure.
String formatRuntime(Duration d) {
  final minutes = d.inMinutes;
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${twoDigits(minutes % 60)}';
}

/// Date locale : `07/11/2026`.
String formatDate(DateTime date) {
  final local = date.toLocal();
  return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year}';
}
