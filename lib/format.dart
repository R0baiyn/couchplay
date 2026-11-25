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

/// Heure locale : `21:05`.
String formatClock(DateTime time) {
  final local = time.toLocal();
  return '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

/// Taille d'un fichier : `350 Mo`, `1,4 Go` (unités de 1000, à la française).
String formatSize(int bytes) {
  String unit(double value, String name) =>
      '${value >= 10 || value == value.roundToDouble() ? value.round() : value.toStringAsFixed(1).replaceFirst('.', ',')} $name';
  if (bytes >= 1000000000) return unit(bytes / 1e9, 'Go');
  if (bytes >= 1000000) return unit(bytes / 1e6, 'Mo');
  if (bytes >= 1000) return unit(bytes / 1e3, 'Ko');
  return '$bytes o';
}
