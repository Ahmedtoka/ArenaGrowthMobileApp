import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/config/env.dart';

part 'group_attachment.freezed.dart';
part 'group_attachment.g.dart';

/// Row from `GET /api/team/groups/{id}/attachments?type=image|file`.
@freezed
class GroupAttachment with _$GroupAttachment {
  const GroupAttachment._();

  const factory GroupAttachment({
    required int id,
    @JsonKey(name: 'message_id') int? messageId,
    @JsonKey(name: 'original_name') String? originalName,
    @JsonKey(name: 'mime_type') String? mimeType,
    @JsonKey(name: 'size_bytes') int? sizeBytes,
    @JsonKey(name: 'sender_name') String? senderName,
    @JsonKey(name: 'sender_id') int? senderId,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _GroupAttachment;

  factory GroupAttachment.fromJson(Map<String, dynamic> json) =>
      _$GroupAttachmentFromJson(json);

  String get downloadUrl =>
      '${Env.apiBaseUrl}/team/attachments/messages/$id';
}

/// Link extracted from a message body.
@freezed
class GroupLink with _$GroupLink {
  const factory GroupLink({
    required String url,
    @JsonKey(name: 'message_id') int? messageId,
    @JsonKey(name: 'sender_name') String? senderName,
    @JsonKey(name: 'sender_id') int? senderId,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _GroupLink;

  factory GroupLink.fromJson(Map<String, dynamic> json) =>
      _$GroupLinkFromJson(json);
}
