import 'package:freezed_annotation/freezed_annotation.dart';

part 'inbox_item.freezed.dart';
part 'inbox_item.g.dart';

@freezed
class InboxSender with _$InboxSender {
  const factory InboxSender({
    required int id,
    required String name,
    @JsonKey(name: 'avatar_color') String? avatarColor,
  }) = _InboxSender;

  factory InboxSender.fromJson(Map<String, dynamic> json) =>
      _$InboxSenderFromJson(json);
}

/// Compact shape from `MeController::inbox` — one row per item across R/O/G.
@freezed
class InboxItem with _$InboxItem {
  const factory InboxItem({
    required int id,
    @JsonKey(name: 'group_id') required int groupId,
    @JsonKey(name: 'brand_name') String? brandName,
    @JsonKey(name: 'group_name') String? groupName,
    required String type,
    @JsonKey(name: 'importance_status') String? importanceStatus,
    @JsonKey(name: 'body_excerpt') String? bodyExcerpt,
    InboxSender? sender,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'marked_red_at') DateTime? markedRedAt,
    @JsonKey(name: 'marked_orange_at') DateTime? markedOrangeAt,
    @JsonKey(name: 'marked_green_at') DateTime? markedGreenAt,
  }) = _InboxItem;

  factory InboxItem.fromJson(Map<String, dynamic> json) =>
      _$InboxItemFromJson(json);
}

@freezed
class InboxBundle with _$InboxBundle {
  // Required for the `total` getter below — freezed needs a private
  // unnamed constructor before it'll allow extra methods on the class.
  const InboxBundle._();

  const factory InboxBundle({
    @Default(0) int redCount,
    @Default(0) int orangeCount,
    @Default(0) int greenCount,
    @Default([]) List<InboxItem> red,
    @Default([]) List<InboxItem> orange,
    @Default([]) List<InboxItem> green,
  }) = _InboxBundle;

  int get total => redCount + orangeCount + greenCount;
}
