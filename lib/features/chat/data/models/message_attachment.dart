import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/config/env.dart';

part 'message_attachment.freezed.dart';
part 'message_attachment.g.dart';

/// Mirrors a row from `tos_message_attachments`.
///
/// The server doesn't include a `url` field in the JSON shape — to display
/// the file we use [downloadUrl] which builds the API path manually.
@freezed
class MessageAttachment with _$MessageAttachment {
  const MessageAttachment._();

  const factory MessageAttachment({
    required int id,
    @JsonKey(name: 'message_id') required int messageId,
    String? disk,
    required String path,
    @JsonKey(name: 'original_name') String? originalName,
    @JsonKey(name: 'mime_type') String? mimeType,
    @JsonKey(name: 'size_bytes') int? sizeBytes,
  }) = _MessageAttachment;

  factory MessageAttachment.fromJson(Map<String, dynamic> json) =>
      _$MessageAttachmentFromJson(json);

  bool get isImage => (mimeType ?? '').startsWith('image/');
  bool get isVoice => const [
        'audio/webm',
        'audio/ogg',
        'audio/mpeg',
        'audio/mp4',
        'audio/aac',
        'audio/wav',
        'audio/x-m4a',
      ].contains(mimeType);
  bool get isVideo => (mimeType ?? '').startsWith('video/');

  /// URL to fetch the binary. Goes through the Sanctum-authed API endpoint.
  String get downloadUrl {
    return '${Env.apiBaseUrl}/team/attachments/messages/$id';
  }
}
