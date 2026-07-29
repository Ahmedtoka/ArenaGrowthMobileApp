import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';
import 'leave_models.dart';

class LeaveRepository {
  final DioClient _client;
  LeaveRepository(this._client);

  String _d(DateTime v) =>
      '${v.year.toString().padLeft(4, '0')}-'
      '${v.month.toString().padLeft(2, '0')}-'
      '${v.day.toString().padLeft(2, '0')}';

  List<LeaveRequestModel> _list(dynamic raw) =>
      ((raw as List<dynamic>?) ?? const [])
          .map((e) => LeaveRequestModel.fromJson(e as Map<String, dynamic>))
          .toList();

  /// My requests + my balance.
  Future<MyLeaves> mine() async {
    final res = await _client.get(ApiConstants.leavesMine);
    final d = res.data as Map<String, dynamic>;
    return MyLeaves(
      requests: _list(d['requests']),
      balance: LeaveBalance.fromJson((d['balance'] as Map?)?.cast<String, dynamic>()),
    );
  }

  Future<LeaveBalance> balance() async {
    final res = await _client.get(ApiConstants.leavesBalance);
    final d = res.data as Map<String, dynamic>;
    return LeaveBalance.fromJson((d['balance'] as Map?)?.cast<String, dynamic>());
  }

  /// Raise a request.
  Future<void> request({
    required String type,
    required DateTime start,
    required DateTime end,
    String? reason,
  }) async {
    await _client.post(ApiConstants.leaves, data: {
      'type': type,
      'start_date': _d(start),
      'end_date': _d(end),
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    },);
  }

  /// Requests awaiting my approval (managers).
  Future<List<LeaveRequestModel>> pending() async {
    final res = await _client.get(ApiConstants.leavesPending);
    return _list((res.data as Map<String, dynamic>)['requests']);
  }

  Future<void> approve(int id) => _client.post(ApiConstants.leaveApprove(id));

  Future<void> reject(int id, {String? note}) => _client.post(
        ApiConstants.leaveReject(id),
        data: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
      );

  Future<void> cancel(int id) => _client.post(ApiConstants.leaveCancel(id));
}
