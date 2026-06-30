import 'package:freezed_annotation/freezed_annotation.dart';

part 'last_message_preview.freezed.dart';
part 'last_message_preview.g.dart';

/// Slim message preview attached to each BrandGroup in the chats list.
@freezed
class LastMessagePreview with _$LastMessagePreview {
  const factory LastMessagePreview({
    required int id,
    @JsonKey(name: 'body_excerpt') String? bodyExcerpt,
    required String type,
    @JsonKey(name: 'sender_id') int? senderId,
    @JsonKey(name: 'sender_name') String? senderName,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _LastMessagePreview;

  factory LastMessagePreview.fromJson(Map<String, dynamic> json) =>
      _$LastMessagePreviewFromJson(json);
}
