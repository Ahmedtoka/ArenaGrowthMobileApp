/// Plain-Dart models for the leave feature (no codegen).

class LeaveBalance {
  final int year;
  final int allocation;
  final int used;
  final int pending;
  final int remaining;

  const LeaveBalance({
    this.year = 0,
    this.allocation = 0,
    this.used = 0,
    this.pending = 0,
    this.remaining = 0,
  });

  factory LeaveBalance.fromJson(Map<String, dynamic>? j) {
    j ??= const {};
    int n(dynamic v) => v is int ? v : int.tryParse('${v ?? 0}') ?? 0;
    return LeaveBalance(
      year: n(j['year']),
      allocation: n(j['allocation']),
      used: n(j['used']),
      pending: n(j['pending']),
      remaining: n(j['remaining']),
    );
  }
}

class LeaveRequestModel {
  final int id;
  final int userId;
  final String? userName;
  final String type;
  final DateTime? start;
  final DateTime? end;
  final int days;
  final String? reason;
  final String status; // pending | approved | rejected | cancelled
  final String statusLabel;
  final String? reviewedBy;
  final String? reviewNote;

  const LeaveRequestModel({
    required this.id,
    required this.userId,
    this.userName,
    required this.type,
    this.start,
    this.end,
    required this.days,
    this.reason,
    required this.status,
    required this.statusLabel,
    this.reviewedBy,
    this.reviewNote,
  });

  bool get isPending => status == 'pending';

  factory LeaveRequestModel.fromJson(Map<String, dynamic> j) {
    int n(dynamic v) => v is int ? v : int.tryParse('${v ?? 0}') ?? 0;
    DateTime? d(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
    return LeaveRequestModel(
      id: n(j['id']),
      userId: n(j['user_id']),
      userName: j['user_name']?.toString(),
      type: (j['type'] ?? 'annual').toString(),
      start: d(j['start_date']),
      end: d(j['end_date']),
      days: n(j['days']),
      reason: j['reason']?.toString(),
      status: (j['status'] ?? 'pending').toString(),
      statusLabel: (j['status_label'] ?? j['status'] ?? '').toString(),
      reviewedBy: j['reviewed_by']?.toString(),
      reviewNote: j['review_note']?.toString(),
    );
  }
}

class MyLeaves {
  final List<LeaveRequestModel> requests;
  final LeaveBalance balance;
  const MyLeaves({required this.requests, required this.balance});
}
