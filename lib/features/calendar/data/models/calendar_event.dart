import 'package:freezed_annotation/freezed_annotation.dart';

part 'calendar_event.freezed.dart';
part 'calendar_event.g.dart';

/// Mirrors `MeController::calendar` event shape.
@freezed
class CalendarEvent with _$CalendarEvent {
  const factory CalendarEvent({
    required int id,
    String? title,
    String? details,
    @JsonKey(name: 'source_type') String? sourceType,
    @JsonKey(name: 'source_id') int? sourceId,
    @JsonKey(name: 'starts_at') DateTime? startsAt,
    @JsonKey(name: 'ends_at') DateTime? endsAt,
    String? color,
  }) = _CalendarEvent;

  factory CalendarEvent.fromJson(Map<String, dynamic> json) =>
      _$CalendarEventFromJson(json);
}
