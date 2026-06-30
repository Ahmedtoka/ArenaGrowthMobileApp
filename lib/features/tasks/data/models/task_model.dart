import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../auth/data/models/user_model.dart';
import '../../../chat/data/models/brand_model.dart';

part 'task_model.freezed.dart';
part 'task_model.g.dart';

/// 9-status state machine — keep as raw strings to match Laravel backend.
class TaskStatus {
  static const pending = 'pending';
  static const inProgress = 'in_progress';
  static const done = 'done';
  /// Sprint R — between `done` and `approved`. Creator (or owner / brand
  /// admin) acknowledged receipt of the deliverable and is reviewing
  /// (typically sharing with the client) before final approval.
  static const received = 'received';
  static const approved = 'approved';
  static const awaitingClarification = 'awaiting_clarification';
  static const resumed = 'resumed';
  static const archived = 'archived';
  static const cancelled = 'cancelled';
}

class TaskPriority {
  static const low = 'low';
  static const normal = 'normal';
  static const high = 'high';
  static const urgent = 'urgent';
}

@freezed
class TaskTimestamps with _$TaskTimestamps {
  const factory TaskTimestamps({
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
    @JsonKey(name: 'first_opened_at') DateTime? firstOpenedAt,
    @JsonKey(name: 'started_working_at') DateTime? startedWorkingAt,
    @JsonKey(name: 'clarification_requested_at') DateTime? clarificationRequestedAt,
    @JsonKey(name: 'clarification_replied_at') DateTime? clarificationRepliedAt,
    @JsonKey(name: 'resumed_work_at') DateTime? resumedWorkAt,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
    // Sprint R — Received marker (between completed and approved).
    @JsonKey(name: 'received_at') DateTime? receivedAt,
    @JsonKey(name: 'approved_at') DateTime? approvedAt,
    @JsonKey(name: 'cancelled_at') DateTime? cancelledAt,
    @JsonKey(name: 'archived_at') DateTime? archivedAt,
    @JsonKey(name: 'due_at') DateTime? dueAt,
  }) = _TaskTimestamps;

  factory TaskTimestamps.fromJson(Map<String, dynamic> json) =>
      _$TaskTimestampsFromJson(json);
}

/// Mirrors `tos_task_attachments` row. `url` is a presigned/authed download
/// link the client can pop into Image.network() (for images) or launchUrl()
/// (for files/links).
@freezed
class TaskAttachment with _$TaskAttachment {
  const factory TaskAttachment({
    required int id,
    @JsonKey(name: 'original_name') String? originalName,
    @JsonKey(name: 'mime_type') String? mimeType,
    @JsonKey(name: 'size_bytes') int? sizeBytes,
    required String url,
    @JsonKey(name: 'uploaded_by_id') int? uploadedById,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    // Sprint J.2 — lifecycle stage: 'initial' (brief), 'completion'
    // (deliverable), or 'update' (mid-work progress). Defaults to
    // 'initial' for older payloads that didn't include this field.
    @JsonKey(name: 'kind') @Default('initial') String kind,
  }) = _TaskAttachment;

  factory TaskAttachment.fromJson(Map<String, dynamic> json) =>
      _$TaskAttachmentFromJson(json);
}

/// Convenience kind constants for filtering attachment lists by lifecycle
/// stage — kept here so screens don't have to remember the wire strings.
class TaskAttachmentKind {
  static const String initial = 'initial';
  static const String completion = 'completion';
  static const String update = 'update';
}

@freezed
class TaskRevision with _$TaskRevision {
  const factory TaskRevision({
    required int id,
    @JsonKey(name: 'requested_by_id') int? requestedById,
    @JsonKey(name: 'requested_at') DateTime? requestedAt,
    @JsonKey(name: 'replied_at') DateTime? repliedAt,
    // Per-cycle resume time. Set when the assignee clicks "Start working
    // again" after this specific clarification reply. NULL while the cycle
    // is open.
    @JsonKey(name: 'resumed_at') DateTime? resumedAt,
    @JsonKey(name: 'clarification_text') String? clarificationText,
    @JsonKey(name: 'reply_text') String? replyText,
    @JsonKey(name: 'response_label') String? responseLabel,
  }) = _TaskRevision;

  factory TaskRevision.fromJson(Map<String, dynamic> json) =>
      _$TaskRevisionFromJson(json);
}

@freezed
class TaskModel with _$TaskModel {
  const TaskModel._();

  const factory TaskModel({
    required int id,
    @JsonKey(name: 'brand_id') int? brandId,
    required String title,
    String? description,
    required String status,
    @JsonKey(name: 'status_label') String? statusLabel,
    String? priority,
    String? department,
    @JsonKey(name: 'assigned_to_id') int? assignedToId,
    @JsonKey(name: 'created_by_id') int? createdById,
    @Default([]) List<String> tags,
    /// Quantified deliverables: [{type, qty, done}]. Raw maps so we don't need
    /// a generated sub-model.
    @Default([]) List<dynamic> deliverables,
    @JsonKey(name: 'is_mine') @Default(false) bool isMine,
    @JsonKey(name: 'is_overdue') @Default(false) bool isOverdue,
    @JsonKey(name: 'revision_count') @Default(0) int revisionCount,
    // Task chain (handoff pipeline). source/root link this task into a
    // project chain; hasChildren means it was already handed off onward.
    @JsonKey(name: 'source_task_id') int? sourceTaskId,
    @JsonKey(name: 'root_task_id') int? rootTaskId,
    @JsonKey(name: 'has_children') @Default(false) bool hasChildren,
    TaskTimestamps? timestamps,
    BrandModel? brand,
    UserModel? assignee,
    UserModel? creator,
    /// Sprint R — who marked the task as received + the optional note
    /// they left (e.g. "sent to client X for review").
    UserModel? receiver,
    @JsonKey(name: 'received_note') String? receivedNote,
    @Default([]) List<TaskRevision> revisions,
    @Default([]) List<TaskAttachment> attachments,
  }) = _TaskModel;

  factory TaskModel.fromJson(Map<String, dynamic> json) =>
      _$TaskModelFromJson(json);

  /// Part of a handoff chain (has a parent, a root, or onward children).
  bool get isChained =>
      sourceTaskId != null || rootTaskId != null || hasChildren;

  bool get isPending => status == TaskStatus.pending;
  bool get isInProgress => status == TaskStatus.inProgress;
  bool get isDone => status == TaskStatus.done;
  bool get isReceived => status == TaskStatus.received;
  bool get isApproved => status == TaskStatus.approved;
  bool get isAwaitingClarification => status == TaskStatus.awaitingClarification;
  bool get isTerminal =>
      status == TaskStatus.archived || status == TaskStatus.cancelled;

  bool get canOpen => isPending;
  bool get canStart => isPending || status == TaskStatus.resumed;
  bool get canRequestClarification => isInProgress || isPending;
  // Complete is ONLY available once the task is actively in progress — i.e.
  // the assignee pressed "Start working". A pending / awaiting-clarification /
  // resumed task must be (re)started first so the work clock is running and
  // points/time are computed correctly.
  bool get canComplete => isInProgress;
  // The creator can post a clarification reply (resumes the task).
  bool get canReplyClarification => isAwaitingClarification;
  // Sprint R — Receive becomes the mandatory gateway from DONE.
  // Approve/Reject only available AFTER receive (status == received).
  bool get canReceive => isDone;
  bool get canApprove => isReceived;
  bool get canReject => isReceived;
}
