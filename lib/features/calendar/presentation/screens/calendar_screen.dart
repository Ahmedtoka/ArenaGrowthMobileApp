import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/text_direction_util.dart';
import '../../data/models/calendar_event.dart';
import '../controllers/calendar_providers.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime? _selected = DateTime.now();
  CalendarFormat _format = CalendarFormat.month;

  ({DateTime from, DateTime to}) _monthRange(DateTime d) {
    final from = DateTime(d.year, d.month - 1, 15);
    final to = DateTime(d.year, d.month + 1, 15);
    return (from: from, to: to);
  }

  @override
  Widget build(BuildContext context) {
    final range = _monthRange(_focused);
    final eventsAsync = ref.watch(calendarEventsProvider(range));

    return Scaffold(
      backgroundColor: AppColors.appBg,
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(calendarEventsProvider(range)),
          ),
        ],
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('Could not load calendar\n$e', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      ref.invalidate(calendarEventsProvider(range)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (events) => _buildBody(events),
      ),
    );
  }

  Widget _buildBody(List<CalendarEvent> events) {
    // Bucket events by yyyy-MM-dd
    final byDay = <DateTime, List<CalendarEvent>>{};
    for (final e in events) {
      final d = e.startsAt;
      if (d == null) continue;
      final key = DateTime(d.year, d.month, d.day);
      (byDay[key] ??= []).add(e);
    }
    final selected = _selected ?? DateTime.now();
    final selectedKey = DateTime(selected.year, selected.month, selected.day);
    final dayEvents = byDay[selectedKey] ?? const [];

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.all(6),
          child: TableCalendar<CalendarEvent>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focused,
            calendarFormat: _format,
            selectedDayPredicate: (d) => isSameDay(d, _selected),
            availableCalendarFormats: const {
              CalendarFormat.month: 'Month',
              CalendarFormat.week: 'Week',
            },
            locale: 'en',
            startingDayOfWeek: StartingDayOfWeek.monday,
            eventLoader: (d) =>
                byDay[DateTime(d.year, d.month, d.day)] ?? const [],
            onDaySelected: (s, f) {
              setState(() {
                _selected = s;
                _focused = f;
              });
            },
            onPageChanged: (f) => setState(() => _focused = f),
            onFormatChanged: (f) => setState(() => _format = f),
            calendarStyle: const CalendarStyle(
              outsideDaysVisible: false,
              todayDecoration: BoxDecoration(
                color: AppColors.arenaBlueLight,
                shape: BoxShape.circle,
              ),
              todayTextStyle: TextStyle(color: AppColors.arenaBlue),
              selectedDecoration: BoxDecoration(
                color: AppColors.arenaBlue,
                shape: BoxShape.circle,
              ),
              markerDecoration: BoxDecoration(
                color: AppColors.arenaRed,
                shape: BoxShape.circle,
              ),
            ),
            headerStyle: const HeaderStyle(
              titleCentered: true,
              formatButtonVisible: true,
            ),
          ),
        ),
        Expanded(
          child: dayEvents.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_busy, size: 56, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No events on this day',
                          style: TextStyle(color: AppColors.ink3),),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: dayEvents.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) => _EventRow(event: dayEvents[i]),
                ),
        ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  final CalendarEvent event;
  const _EventRow({required this.event});

  Color get _color {
    final hex = event.color;
    if (hex == null || hex.isEmpty) return AppColors.arenaBlue;
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return AppColors.arenaBlue;
    final value = int.tryParse(h, radix: 16);
    return value == null ? AppColors.arenaBlue : Color(value);
  }

  IconData get _icon {
    switch (event.sourceType) {
      case 'meeting':
        return Icons.event;
      case 'task':
        return Icons.task_alt;
      case 'reminder':
        return Icons.notifications;
      default:
        return Icons.event_note;
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = event.startsAt;
    final end = event.endsAt;
    final title = event.title ?? 'Event';
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Type/brand color accent stripe.
            Container(width: 4, color: _color),
            Expanded(
              child: Container(
                color: Colors.white,
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_icon, color: _color, size: 20),
                  ),
                  title: Text(
                    title,
                    textDirection: detectBidiDirection(title),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (start != null)
                        Text(
                          end == null
                              ? DateFormat('h:mm a').format(start.toLocal())
                              : '${DateFormat('h:mm a').format(start.toLocal())} - ${DateFormat('h:mm a').format(end.toLocal())}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.ink2,),
                        ),
                      if (event.details != null && event.details!.isNotEmpty)
                        Text(
                          event.details!,
                          textDirection: detectBidiDirection(event.details),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.ink3,),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
