import 'package:freezed_annotation/freezed_annotation.dart';

import 'message_attachment.dart';

part 'message_model.freezed.dart';
part 'message_model.g.dart';

/// The API returns a nested `pin` object when a message is pinned (or null).
/// We only care about presence → a boolean flag.
bool _pinExists(Object? json) => json != null;

/// Pull the reactor's display name out of the nested `user` object.
String? _reactionUserName(Object? json) =>
    json is Map ? json['name'] as String? : null;

/// Slim sender shape used inside Message rows (subset of UserResource).
@freezed
class MessageSender with _$MessageSender {
  const factory MessageSender({
    required int id,
    required String name,
    String? email,
    @JsonKey(name: 'avatar_color') String? avatarColor,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    String? initials,
  }) = _MessageSender;

  factory MessageSender.fromJson(Map<String, dynamic> json) =>
      _$MessageSenderFromJson(json);
}

/// One emoji reaction row (subset of `tos_message_reactions`).
@freezed
class MessageReaction with _$MessageReaction {
  const factory MessageReaction({
    @JsonKey(name: 'user_id') required int userId,
    required String emoji,
    @JsonKey(name: 'user', fromJson: _reactionUserName) String? userName,
  }) = _MessageReaction;

  factory MessageReaction.fromJson(Map<String, dynamic> json) =>
      _$MessageReactionFromJson(json);
}

/// Importance status — keep as raw string to match backend enum.
class MessageImportance {
  static const normal = 'normal';
  static const red = 'red';
  static const orange = 'orange';
  static const green = 'green';
}

/// Message type — matches `App\TeamOS\Models\Message::TYPE_*` constants.
class MessageType {
  static const text = 'text';
  static const voice = 'voice';
  static const file = 'file';
  static const image = 'image';
  static const poll = 'poll';
  static const system = 'system';
  static const taskCard = 'task_card';
  static const meetingCard = 'meeting_card';
  static const taskDone = 'task_done';
  static const clarification = 'clarification_request';
  static const clarificationReply = 'clarification_reply';
}

/// Mirrors a row from `GET /api/team/groups/{group}/messages`.
///
/// The controller returns raw Eloquent models with their loaded relations,
/// so the shape is the database columns + nested sender/mentions/attachments.
@freezed
class MessageModel with _$MessageModel {
  const factory MessageModel({
    required int id,
    @JsonKey(name: 'brand_group_id') required int brandGroupId,
    @JsonKey(name: 'user_id') required int userId,
    @JsonKey(name: 'reply_to_id') int? replyToId,
    @JsonKey(name: 'thread_root_id') int? threadRootId,
    required String type,
    String? body,
    @JsonKey(name: 'forwarded_from') String? forwardedFrom,
    @JsonKey(name: 'link_preview') Map<String, dynamic>? linkPreview,
    Map<String, dynamic>? payload,
    @JsonKey(name: 'importance_status') @Default('normal') String importanceStatus,
    @JsonKey(name: 'marked_red_at') DateTime? markedRedAt,
    @JsonKey(name: 'marked_orange_at') DateTime? markedOrangeAt,
    @JsonKey(name: 'marked_green_at') DateTime? markedGreenAt,
    @JsonKey(name: 'edited_at') DateTime? editedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
    MessageSender? sender,
    @Default([]) List<MessageAttachment> attachments,
    @Default([]) List<MessageReaction> reactions,
    // The API sends a nested `pin` object (or null); we only need presence.
    @JsonKey(name: 'pin', fromJson: _pinExists) @Default(false) bool isPinned,
    // Read receipts: how many OTHER members have seen this message.
    @JsonKey(name: 'seen_by_count') @Default(0) int seenByCount,
    // True only when EVERY other group member has seen it → blue double-tick.
    @JsonKey(name: 'seen_by_all') @Default(false) bool seenByAll,
  }) = _MessageModel;

  factory MessageModel.fromJson(Map<String, dynamic> json) =>
      _$MessageModelFromJson(json);
}

extension MessageModelX on MessageModel {
  bool get isRed => importanceStatus == MessageImportance.red;
  bool get isOrange => importanceStatus == MessageImportance.orange;
  bool get isGreen => importanceStatus == MessageImportance.green;
  bool get isSystemCard => const [
        MessageType.system,
        MessageType.taskCard,
        MessageType.meetingCard,
        MessageType.taskDone,
        MessageType.clarification,
        MessageType.clarificationReply,
      ].contains(type);
  bool get isText => type == MessageType.text;
  bool get isDeleted => deletedAt != null;

  /// emoji → count, preserving first-seen order.
  Map<String, int> get reactionCounts {
    final m = <String, int>{};
    for (final r in reactions) {
      m[r.emoji] = (m[r.emoji] ?? 0) + 1;
    }
    return m;
  }

  bool didReact(String emoji, int myUserId) =>
      reactions.any((r) => r.emoji == emoji && r.userId == myUserId);

  /// Display names of everyone who reacted with [emoji].
  List<String> reactorNames(String emoji) => reactions
      .where((r) => r.emoji == emoji)
      .map((r) => r.userName ?? 'Someone')
      .toList();
}
