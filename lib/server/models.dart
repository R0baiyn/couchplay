import 'json_read.dart';

/// État de l'abonnement, tel que le serveur le décrit dans `user_info`.
final class AccountInfo {
  const AccountInfo({
    required this.status,
    this.expiresAt,
    this.maxConnections,
    this.activeConnections,
    this.isTrial = false,
  });

  /// Lit `user_info` ; les champs absents ou illisibles restent à `null`.
  factory AccountInfo.fromJson(Map<String, Object?> userInfo) => AccountInfo(
    status: asString(userInfo['status'])?.trim() ?? 'Inconnu',
    expiresAt: asDate(userInfo['exp_date']),
    maxConnections: asInt(userInfo['max_connections']),
    activeConnections: asInt(userInfo['active_cons']),
    isTrial: asBool(userInfo['is_trial']) ?? false,
  );

  /// Texte du serveur, en anglais : `Active`, `Expired`, `Banned`, `Disabled`…
  final String status;

  /// `null` quand l'abonnement n'expire pas.
  final DateTime? expiresAt;

  final int? maxConnections;
  final int? activeConnections;
  final bool isTrial;

  bool get isActive => status.toLowerCase() == 'active';
}
