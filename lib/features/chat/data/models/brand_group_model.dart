import 'package:freezed_annotation/freezed_annotation.dart';

import 'brand_model.dart';
import 'last_message_preview.dart';

part 'brand_group_model.freezed.dart';
part 'brand_group_model.g.dart';

/// The OTHER participant of a 1-on-1 direct thread (relative to the viewer).
/// The backend resolves this per-request so the title/avatar can show the
/// person you're talking to instead of the stored "A ⇄ B" group name.
@freezed
class DirectCounterpart with _$DirectCounterpart {
  const factory DirectCounterpart({
    required int id,
    required String name,
    @JsonKey(name: 'avatar_color') String? avatarColor,
    @JsonKey(name: 'avatar_path') String? avatarPath,
    String? department,
  }) = _DirectCounterpart;

  factory DirectCounterpart.fromJson(Map<String, dynamic> json) =>
      _$DirectCounterpartFromJson(json);
}

/// Mirrors `App\Http\Resources\TeamOS\BrandGroupResource`.
@freezed
class BrandGroupModel with _$BrandGroupModel {
  // Private ctor enables custom getters (displayName) on the freezed class so
  // they're available everywhere the type is used — no extension import needed.
  const BrandGroupModel._();

  const factory BrandGroupModel({
    required int id,
    @JsonKey(name: 'brand_id') required int brandId,
    @JsonKey(name: 'parent_group_id') int? parentGroupId,
    required String name,
    String? description,
    String? type,
    @JsonKey(name: 'is_direct') @Default(false) bool isDirect,
    @JsonKey(name: 'is_custom') @Default(false) bool isCustom,
    @JsonKey(name: 'photo_url') String? photoUrl,
    @JsonKey(name: 'other_user') DirectCounterpart? otherUser,
    @JsonKey(name: 'last_message_at') DateTime? lastMessageAt,
    @JsonKey(name: 'message_count') @Default(0) int messageCount,
    @JsonKey(name: 'archived_at') DateTime? archivedAt,
    @JsonKey(name: 'pinned_at') DateTime? pinnedAt,
    @JsonKey(name: 'last_read_message_id') int? lastReadMessageId,
    @JsonKey(name: 'unread_count') @Default(0) int unreadCount,
    @JsonKey(name: 'open_mention_count') @Default(0) int openMentionCount,
    BrandModel? brand,
    @JsonKey(name: 'last_message') LastMessagePreview? lastMessage,
  }) = _BrandGroupModel;

  factory BrandGroupModel.fromJson(Map<String, dynamic> json) =>
      _$BrandGroupModelFromJson(json);

  /// The title to show: for a direct thread, the OTHER person's name; for a
  /// real group, the group's own name. Falls back to the stored name.
  String get displayName => isDirect ? (otherUser?.name ?? name) : name;
}
