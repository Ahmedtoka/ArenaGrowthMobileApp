import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/providers/app_providers.dart';
import '../models/attendance_snapshot.dart';

/// Thin wrapper around the five attendance endpoints. All actions return
/// the fresh snapshot so the caller can update local state in one shot.
///
/// Uses [DioClient] (not raw Dio) so request errors are uniformly mapped to
/// [ApiException] with the server's `message` field already pulled out.
class AttendanceRepository {
  final DioClient _client;
  const AttendanceRepository(this._client);

  Future<AttendanceSnapshot> today() async {
    final res = await _client.get(ApiConstants.attendanceToday);
    return AttendanceSnapshot.fromJson(res.data as Map<String, dynamic>);
  }

  Future<AttendanceSnapshot> checkIn({
    double? latitude,
    double? longitude,
    int? accuracyMeters,
    String? note,
  }) async {
    final res = await _client.post(
      ApiConstants.attendanceCheckIn,
      data: {
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    return AttendanceSnapshot.fromJson(res.data as Map<String, dynamic>);
  }

  Future<AttendanceSnapshot> checkOut({
    double? latitude,
    double? longitude,
    int? accuracyMeters,
  }) async {
    final res = await _client.post(
      ApiConstants.attendanceCheckOut,
      data: {
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
      },
    );
    return AttendanceSnapshot.fromJson(res.data as Map<String, dynamic>);
  }

  Future<AttendanceSnapshot> breakStart({
    double? latitude,
    double? longitude,
    int? accuracyMeters,
  }) async {
    final res = await _client.post(
      ApiConstants.attendanceBreakStart,
      data: {
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
      },
    );
    return AttendanceSnapshot.fromJson(res.data as Map<String, dynamic>);
  }

  Future<AttendanceSnapshot> breakEnd({
    double? latitude,
    double? longitude,
    int? accuracyMeters,
  }) async {
    final res = await _client.post(
      ApiConstants.attendanceBreakEnd,
      data: {
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
      },
    );
    return AttendanceSnapshot.fromJson(res.data as Map<String, dynamic>);
  }

  /// Flip the user's availability (on-duty/off-duty) without touching the
  /// open session. Used by the "Go away" / "I'm back" buttons.
  /// Coordinates are recorded server-side so the admin Check-ins log shows
  /// WHERE the user went away / came back.
  Future<AttendanceSnapshot> setAvailability(
    bool available, {
    double? lat,
    double? lng,
    int? accuracy,
    String? reason,
  }) async {
    final res = await _client.post(
      ApiConstants.attendanceAvailability,
      data: {
        'available': available,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (lat != null) 'latitude': lat,
        if (lng != null) 'longitude': lng,
        if (accuracy != null) 'accuracy_meters': accuracy,
      },
    );
    return AttendanceSnapshot.fromJson(res.data as Map<String, dynamic>);
  }
}

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(ref.read(dioClientProvider)),
);
