import 'package:intl/intl.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/providers/app_providers.dart';
import '../../data/models/calendar_event.dart';

part 'calendar_providers.g.dart';

/// Loads calendar events for the given month window.
@riverpod
Future<List<CalendarEvent>> calendarEvents(
  CalendarEventsRef ref,
  ({DateTime from, DateTime to}) range,
) async {
  final client = ref.read(dioClientProvider);
  final res = await client.get(
    ApiConstants.myCalendar,
    query: {
      'from': DateFormat('yyyy-MM-dd').format(range.from),
      'to': DateFormat('yyyy-MM-dd').format(range.to),
    },
  );
  final data = res.data as Map<String, dynamic>;
  final events = (data['events'] ?? const []) as List<dynamic>;
  return events
      .map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>))
      .toList();
}
