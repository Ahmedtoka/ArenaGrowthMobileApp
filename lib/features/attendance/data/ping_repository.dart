import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/providers/app_providers.dart';

/// One location sample collected client-side and waiting to be flushed
/// to the server.
class PendingPing {
  final double latitude;
  final double longitude;
  final int? accuracyMeters;
  final int? batteryPct;
  final bool isAppForeground;
  final DateTime reportedAt;

  const PendingPing({
    required this.latitude,
    required this.longitude,
    required this.reportedAt,
    this.accuracyMeters,
    this.batteryPct,
    this.isAppForeground = true,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
        if (batteryPct != null) 'battery_pct': batteryPct,
        'is_app_foreground': isAppForeground,
        'reported_at': reportedAt.toUtc().toIso8601String(),
      };
}

/// Thin wrapper around the batched-pings endpoint. The server returns
/// `accepted: 0, reason: 'not_checked_in'` if the user has already checked
/// out — callers should stop streaming when they see that.
class PingRepository {
  final DioClient _client;
  const PingRepository(this._client);

  /// Returns the server-reported number of pings accepted. 0 means the
  /// session was closed — the caller should stop the timer.
  Future<({int accepted, String? reason})> flush(List<PendingPing> pings) async {
    if (pings.isEmpty) return (accepted: 0, reason: 'empty');
    final res = await _client.post(
      ApiConstants.attendancePings,
      data: {'pings': pings.map((p) => p.toJson()).toList()},
    );
    final body = res.data as Map<String, dynamic>;
    return (
      accepted: (body['accepted'] as num?)?.toInt() ?? 0,
      reason: body['reason'] as String?,
    );
  }
}

final pingRepositoryProvider = Provider<PingRepository>(
  (ref) => PingRepository(ref.read(dioClientProvider)),
);
