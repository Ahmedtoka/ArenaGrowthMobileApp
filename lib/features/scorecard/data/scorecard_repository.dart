import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';

/// The authenticated employee's own monthly scorecard
/// (attendance + tasks + points + ratings + payslip).
class ScorecardRepository {
  final DioClient _client;
  ScorecardRepository(this._client);

  /// GET /api/team/me/scorecard?year=&month=
  Future<Map<String, dynamic>> fetch({int? year, int? month}) async {
    final query = <String, dynamic>{};
    if (year != null) query['year'] = year;
    if (month != null) query['month'] = month;
    final res = await _client.get(ApiConstants.myScorecard, query: query);
    return (res.data as Map).cast<String, dynamic>();
  }

  /// GET /api/team/me/scorecard/detail?source=&year=&month=
  /// The per-event records behind one points source (why each point was earned).
  /// Returns {category, rows:[…]}.
  Future<Map<String, dynamic>> fetchDetail({
    required String source,
    int? year,
    int? month,
  }) async {
    final query = <String, dynamic>{'source': source};
    if (year != null) query['year'] = year;
    if (month != null) query['month'] = month;
    final res = await _client.get('${ApiConstants.myScorecard}/detail', query: query);
    return (res.data as Map).cast<String, dynamic>();
  }
}
