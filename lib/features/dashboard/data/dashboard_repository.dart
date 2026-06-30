import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';

/// Read-only manager/employee dashboard data source.
///
/// The endpoint is role-aware on the server (owner / account_manager /
/// department_manager / employee). It also accepts a time filter.
class DashboardRepository {
  final DioClient _client;
  DashboardRepository(this._client);

  /// GET /api/team/dashboard → the full summary map.
  ///
  /// Pass [period] ('today' | 'week' | 'half_month' | 'month' | '30d') OR a
  /// custom [from]/[to] range (which takes precedence).
  Future<Map<String, dynamic>> summary({
    String period = 'today',
    DateTime? from,
    DateTime? to,
  }) async {
    final query = <String, dynamic>{};
    if (from != null && to != null) {
      query['period'] = 'custom';
      query['from'] = from.toIso8601String();
      query['to'] = to.toIso8601String();
    } else {
      query['period'] = period;
    }
    final res = await _client.get(ApiConstants.dashboard, query: query);
    return (res.data as Map).cast<String, dynamic>();
  }
}
