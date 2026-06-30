import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:path/path.dart' as p;

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/api_exception.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/utils/upload_prep.dart';
import '../models/brand_group_model.dart';
import '../models/group_attachment.dart';
import '../models/message_model.dart';

class ChatRepository {
  final DioClient _client;

  ChatRepository(this._client);

  /// GET /api/team/me/groups → ordered chats list with preview + unread count.
  Future<List<BrandGroupModel>> listMyGroups() async {
    final res = await _client.get(ApiConstants.myGroups);
    final data = res.data as Map<String, dynamic>;
    final groups = data['groups'] as List<dynamic>;
    return groups
        .map((g) => BrandGroupModel.fromJson(g as Map<String, dynamic>))
        .toList();
  }

  /// POST /api/team/dm → find-or-create the 1-on-1 thread with [userId] and
  /// return it as a group card (so we can navigate straight into the chat).
  Future<BrandGroupModel> openDm(int userId) async {
    final res = await _client.post(ApiConstants.dm, data: {'user_id': userId});
    final data = res.data as Map<String, dynamic>;
    return BrandGroupModel.fromJson(data['group'] as Map<String, dynamic>);
  }

  /// GET /api/team/groups/{id}/pins — pinned messages, newest pin first.
  Future<List<MessageModel>> listPins(int groupId) async {
    final res = await _client.get(ApiConstants.groupPins(groupId));
    final data = res.data as Map<String, dynamic>;
    final list = (data['messages'] as List<dynamic>? ?? const []);
    return list
        .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/team/messages/{id}/seen-by — who has read this message.
  Future<List<Map<String, dynamic>>> messageSeenBy(int messageId) async {
    final res = await _client.get(ApiConstants.messageSeenBy(messageId));
    final data = res.data as Map<String, dynamic>;
    return ((data['seen_by'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// Record that the current user listened to a voice message (idempotent).
  Future<void> markPlayed(int messageId) async {
    await _client.post(ApiConstants.messagePlayed(messageId));
  }

  /// Who has LISTENED to a voice message (distinct from who merely saw it).
  Future<List<Map<String, dynamic>>> messagePlayedBy(int messageId) async {
    final res = await _client.get(ApiConstants.messagePlayedBy(messageId));
    final data = res.data as Map<String, dynamic>;
    return ((data['played_by'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// POST /api/team/messages/{id}/react — toggle an emoji reaction; returns
  /// the refreshed message (with its updated reactions).
  Future<MessageModel> toggleReaction(int messageId, String emoji) async {
    final res = await _client.post(
      ApiConstants.messageReact(messageId),
      data: {'emoji': emoji},
    );
    final data = res.data as Map<String, dynamic>;
    return MessageModel.fromJson(data['message'] as Map<String, dynamic>);
  }

  /// POST /api/team/messages/{id}/pin — toggle pin; returns the new state.
  Future<bool> togglePin(int messageId) async {
    final res = await _client.post(ApiConstants.messagePin(messageId));
    final data = res.data as Map<String, dynamic>;
    return (data['pinned'] as bool?) ?? false;
  }

  /// GET /api/team/groups/{groupId}/messages?before=<id>&limit=<n>
  ///
  /// Returns messages ordered oldest → newest (the backend already reverses).
  Future<List<MessageModel>> getMessages(
    int groupId, {
    int? before,
    int limit = 50,
  }) async {
    final res = await _client.get(
      ApiConstants.groupMessages(groupId),
      query: {
        'limit': limit,
        if (before != null) 'before': before,
      },
    );
    final data = res.data as Map<String, dynamic>;
    final messages = data['messages'] as List<dynamic>;
    return messages
        .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  /// POST /api/team/groups/{groupId}/messages — send a text message.
  Future<MessageModel> sendText(
    int groupId, {
    required String body,
    int? replyToId,
    List<int>? mentions,
  }) async {
    final res = await _client.post(
      ApiConstants.groupMessages(groupId),
      data: {
        'type': 'text',
        'body': body,
        if (replyToId != null) 'reply_to_id': replyToId,
        if (mentions != null && mentions.isNotEmpty) 'mentions': mentions,
      },
    );
    final data = res.data as Map<String, dynamic>;
    final msg = data['message'] as Map<String, dynamic>;
    return MessageModel.fromJson(msg);
  }

  /// POST /api/team/messages/{messageId}/read — mark as seen up to this id.
  Future<void> markRead(int messageId) async {
    await _client.post(ApiConstants.messageRead(messageId));
  }

  /// POST /api/team/groups/{groupId}/read — mark ALL messages in the group
  /// as read up to the latest message. Used when the user opens a chat
  /// so the unread badge in the chats list collapses to 0.
  Future<void> markGroupRead(int groupId) async {
    await _client.post(ApiConstants.groupRead(groupId));
  }

  /// POST /api/team/meetings/{meetingId}/rsvp — respond to a meeting card.
  /// `rsvp` must be one of: accepted, declined, tentative.
  Future<void> rsvpMeeting(int meetingId, String rsvp) async {
    await _client.post(
      ApiConstants.meetingRsvp(meetingId),
      data: {'rsvp': rsvp},
    );
  }

  /// DELETE /api/team/messages/{messageId} — soft-delete a message.
  /// Allowed for the author or owner; 403 otherwise.
  Future<void> deleteMessage(int messageId) async {
    await _client.delete(ApiConstants.message(messageId));
  }

  /// PATCH /api/team/messages/{messageId} — edit own message body.
  /// Stamps `edited_at` so the bubble shows "edited" next to the time
  /// (Sprint P.2).
  Future<MessageModel?> editMessage(int messageId, String newBody) async {
    final res = await _client.patch(
      ApiConstants.message(messageId),
      data: {'body': newBody},
    );
    final m = (res.data as Map<String, dynamic>)['message'];
    if (m is Map<String, dynamic>) return MessageModel.fromJson(m);
    return null;
  }

  /// GET /api/team/groups/{id}/attachments?type=image — list group images.
  Future<List<GroupAttachment>> listImages(int groupId) async {
    final res = await _client.get(
      ApiConstants.groupAttachments(groupId),
      query: {'type': 'image'},
    );
    final data = res.data as Map<String, dynamic>;
    return ((data['images'] ?? const []) as List)
        .map((e) => GroupAttachment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/team/groups/{id}/attachments?type=file — list group files (docs/PDFs/etc).
  Future<List<GroupAttachment>> listFiles(int groupId) async {
    final res = await _client.get(
      ApiConstants.groupAttachments(groupId),
      query: {'type': 'file'},
    );
    final data = res.data as Map<String, dynamic>;
    return ((data['files'] ?? const []) as List)
        .map((e) => GroupAttachment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/team/groups/{id}/attachments?type=link — extracted message links.
  Future<List<GroupLink>> listLinks(int groupId) async {
    final res = await _client.get(
      ApiConstants.groupAttachments(groupId),
      query: {'type': 'link'},
    );
    final data = res.data as Map<String, dynamic>;
    return ((data['links'] ?? const []) as List)
        .map((e) => GroupLink.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /api/team/messages/{messageId}/mark-red — flag for action.
  /// Returns the updated message.
  Future<MessageModel> markRed(int messageId) async {
    final res = await _client.post(ApiConstants.messageMarkRed(messageId));
    return _extractMessage(res.data);
  }

  /// POST /api/team/messages/{messageId}/mark-green — approve / close.
  /// (Backend also auto-pins green messages — see MessagePin model.)
  Future<MessageModel> markGreen(int messageId) async {
    final res = await _client.post(ApiConstants.messageMarkGreen(messageId));
    return _extractMessage(res.data);
  }

  /// POST /api/team/messages/{messageId}/revert — clear R/O/G back to normal.
  Future<MessageModel> revert(int messageId) async {
    final res = await _client.post(ApiConstants.messageRevert(messageId));
    return _extractMessage(res.data);
  }

  /// POST /api/team/groups/{groupId}/messages/file — upload image / file.
  ///
  /// Backend infers `image` vs `file` from the mime type. `onProgress` is
  /// called with sent/total bytes during upload.
  Future<MessageModel> sendFile(
    int groupId, {
    required File file,
    String? caption,
    int? replyToId,
    List<int>? mentions,
    void Function(int sent, int total)? onProgress,
  }) async {
    // Shrink huge images BEFORE upload (20MB photo → ~1-2MB). Non-images
    // and small files pass through untouched. Never throws.
    final prepared = await UploadPrep.prepare(file);
    final filename = p.basename(prepared.path);

    // AUTO-RETRY: a flaky-network failure retries up to 2 more times with a
    // short backoff before surfacing the error to the user.
    DioException? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      // FormData can only be consumed once — rebuild per attempt.
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(prepared.path, filename: filename),
        if (caption != null && caption.trim().isNotEmpty) 'body': caption.trim(),
        if (replyToId != null) 'reply_to_id': replyToId,
        if (mentions != null && mentions.isNotEmpty)
          'mentions[]': mentions.map((id) => id.toString()).toList(),
      });

      try {
        final res = await _client.dio.post(
          ApiConstants.groupMessageFile(groupId),
          data: formData,
          onSendProgress: onProgress,
          // Large videos (up to 500MB) can take a while to stream up and for
          // the server to finalize — lift the default 60s receive cap and let
          // the upload itself run unbounded (sendTimeout: null).
          options: Options(
            sendTimeout: const Duration(minutes: 30),
            receiveTimeout: const Duration(minutes: 5),
          ),
        );
        _throwIfNotSuccess(res);
        return _extractMessage(res.data);
      } on DioException catch (e) {
        // Only retry transport-level failures — a 4xx/validation error will
        // fail identically every time.
        final retryable = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError;
        if (!retryable || attempt == 3) rethrow;
        lastError = e;
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    throw lastError!; // unreachable, satisfies the analyzer
  }

  /// POST /api/team/groups/{groupId}/messages/voice — upload voice note.
  Future<MessageModel> sendVoice(
    int groupId, {
    required File file,
    int? durationMs,
    int? replyToId,
    void Function(int sent, int total)? onProgress,
  }) async {
    final filename = p.basename(file.path);
    // Force a mime type the backend whitelist accepts. The `record` package's
    // AAC-LC encoder produces M4A files (AAC in MP4 container). Without an
    // explicit contentType Dio may send octet-stream which fails server
    // validation.
    final contentType = _mediaTypeForVoice(filename);
    final formData = FormData.fromMap({
      'audio': await MultipartFile.fromFile(
        file.path,
        filename: filename,
        contentType: contentType,
      ),
      if (durationMs != null) 'duration_ms': durationMs,
      if (replyToId != null) 'reply_to_id': replyToId,
    });

    final res = await _client.dio.post(
      ApiConstants.groupMessageVoice(groupId),
      data: formData,
      onSendProgress: onProgress,
    );
    _throwIfNotSuccess(res);
    return _extractMessage(res.data);
  }

  MediaType _mediaTypeForVoice(String filename) {
    final ext = p.extension(filename).toLowerCase();
    return switch (ext) {
      '.m4a' || '.mp4' || '.aac' => MediaType('audio', 'mp4'),
      '.mp3' => MediaType('audio', 'mpeg'),
      '.ogg' => MediaType('audio', 'ogg'),
      '.webm' => MediaType('audio', 'webm'),
      '.wav' => MediaType('audio', 'wav'),
      _ => MediaType('audio', 'mp4'),
    };
  }

  /// Raise an ApiException with the server's human-readable message when the
  /// upload didn't return 2xx. Uses `validateStatus: < 500` on Dio so we get
  /// here for 4xx — without this we'd cast the error body's `message` STRING
  /// as if it were a Map and surface a confusing "type String" cast error.
  void _throwIfNotSuccess(Response res) {
    final code = res.statusCode ?? 0;
    if (code >= 200 && code < 300) return;

    final data = res.data;
    String message = 'Send failed';
    Map<String, List<String>>? validationErrors;

    if (data is Map) {
      message = (data['message'] ?? data['error'] ?? message).toString();
      if (data['errors'] is Map) {
        validationErrors = (data['errors'] as Map).map(
          (k, v) => MapEntry(
            k.toString(),
            (v as List).map((e) => e.toString()).toList(),
          ),
        );
        // Surface the first specific error instead of the generic one.
        final first = validationErrors.values
            .expand((list) => list)
            .firstWhere((s) => s.isNotEmpty, orElse: () => '');
        if (first.isNotEmpty) message = first;
      }
    }

    throw ApiException(
      message: message,
      statusCode: code,
      data: data,
      validationErrors: validationErrors,
    );
  }

  MessageModel _extractMessage(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw ApiException(
        message: 'Unexpected response from the server',
        data: data,
      );
    }
    final raw = data['message'];
    if (raw is! Map<String, dynamic>) {
      // Some endpoints (markRed/markGreen) wrap, others return the message
      // at the top level — handle both.
      if (data.containsKey('id')) {
        return MessageModel.fromJson(data);
      }
      throw ApiException(
        message: raw is String ? raw : 'Unexpected response',
        data: data,
      );
    }
    return MessageModel.fromJson(raw);
  }
}
