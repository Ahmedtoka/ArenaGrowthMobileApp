import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../data/shoot_models.dart';
import 'add_shoot_sheet.dart';
import 'shoot_detail_sheet.dart';
import 'shoots_providers.dart';

/// 📸 Shoot calendar ("Cuva") — Calendar (month grid) + List (agenda) views.
/// Each shoot renders as a card: client · time (AM/PM) · location · crew.
class ShootsCalendarScreen extends ConsumerStatefulWidget {
  const ShootsCalendarScreen({super.key});

  @override
  ConsumerState<ShootsCalendarScreen> createState() => _ShootsCalendarScreenState();
}

class _ShootsCalendarScreenState extends ConsumerState<ShootsCalendarScreen> {
  bool _calendar = true;
  late DateTime _month; // first day of shown month
  DateTime? _selected;

  static const _months = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekHeads = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _selected = DateTime(now.year, now.month, now.day);
  }

  // "14:30" → "2:30 PM"
  static String _ampm(String? t) {
    if (t == null || !t.contains(':')) return '';
    final p = t.split(':');
    var h = int.tryParse(p[0]) ?? 0;
    final m = p[1];
    final ap = h >= 12 ? 'PM' : 'AM';
    var hh = h % 12;
    if (hh == 0) hh = 12;
    return '$hh:$m $ap';
  }

  static Color _parse(String? hex, [Color fb = AppColors.arenaBlue]) {
    if (hex == null || hex.isEmpty) return fb;
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? fb : Color(v);
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, List<Shoot>> _group(List<Shoot> shoots) {
    final m = <String, List<Shoot>>{};
    for (final s in shoots.where((s) => !s.isCancelled || true)) {
      m.putIfAbsent(s.date, () => []).add(s);
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(shootsProvider);

    return Scaffold(
      backgroundColor: AppColors.appBg,
      appBar: AppBar(
        title: const Text('Shoot calendar'),
        actions: [
          _Segment(
            calendar: _calendar,
            onChanged: (v) => setState(() => _calendar = v),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: async.valueOrNull?.canManage == true
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.arenaBlue,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Add to Cuva', style: TextStyle(color: Colors.white)),
              onPressed: () => AddShootSheet.show(context),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(shootsProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(children: const [
            SizedBox(height: 120),
            Center(child: Text('Couldn’t load the calendar. Pull to retry.')),
          ]),
          data: (res) => _calendar
              ? _calendarView(res.shoots, res.canManage)
              : _listView(res.shoots, res.canManage),
        ),
      ),
    );
  }

  // ─────────────────────────── CALENDAR ───────────────────────────
  Widget _calendarView(List<Shoot> shoots, bool canManage) {
    final byDate = _group(shoots);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday; // Mon=1..Sun=7
    final lead = (firstWeekday + 1) % 7; // Saturday-first
    final cells = ((lead + daysInMonth) / 7).ceil() * 7;

    final selKey = _selected == null ? null : _dateKey(_selected!);
    final dayShoots = selKey == null ? <Shoot>[] : (byDate[selKey] ?? []);

    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        // Month nav
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1, 1)),
              ),
              Expanded(
                child: Text(
                  '${_months[_month.month]} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1, 1)),
              ),
            ],
          ),
        ),
        // Weekday header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: _weekHeads
                .map((w) => Expanded(
                      child: Center(
                        child: Text(w,
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.ink3)),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 4),
        // Grid
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.78,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: cells,
            itemBuilder: (ctx, i) {
              final dayNum = i - lead + 1;
              final inMonth = dayNum >= 1 && dayNum <= daysInMonth;
              if (!inMonth) return const SizedBox.shrink();
              final date = DateTime(_month.year, _month.month, dayNum);
              final key = _dateKey(date);
              final has = byDate[key] ?? const [];
              final isToday = _isSameDay(date, DateTime.now());
              final isSel = _selected != null && _isSameDay(date, _selected!);
              return GestureDetector(
                onTap: () => setState(() => _selected = date),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSel ? AppColors.arenaBlue : (isToday ? AppColors.arenaBlueLight : Colors.white),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isToday && !isSel ? AppColors.arenaBlue : const Color(0xFFE8ECF2),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNum',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isSel ? Colors.white : (isToday ? AppColors.arenaBlue : AppColors.ink2),
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (has.isNotEmpty)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: has.take(3).map((s) {
                            return Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: isSel ? Colors.white : _parse(s.brandColor),
                                shape: BoxShape.circle,
                              ),
                            );
                          }).toList(),
                        )
                      else
                        const SizedBox(height: 5),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 24),
        // Selected day's shoots
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            _selected == null
                ? 'Pick a day'
                : '${_weekdayName(_selected!)} ${_selected!.day} ${_months[_selected!.month]}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
        ),
        if (dayShoots.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No shoots on this day.', style: TextStyle(color: AppColors.ink3))),
          )
        else
          ...dayShoots.map((s) => _card(s, canManage)),
      ],
    );
  }

  // ─────────────────────────── LIST ───────────────────────────
  Widget _listView(List<Shoot> shoots, bool canManage) {
    final active = shoots.where((s) => !s.isCancelled).toList();
    if (active.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 100),
        Icon(Icons.camera_alt_outlined, size: 56, color: Colors.grey),
        SizedBox(height: 12),
        Center(child: Text('No shoots scheduled yet.', style: TextStyle(color: AppColors.ink3))),
      ]);
    }
    final byDate = <String, List<Shoot>>{};
    for (final s in active) {
      byDate.putIfAbsent(s.date, () => []).add(s);
    }
    final items = <Widget>[];
    byDate.forEach((date, list) {
      final d = DateTime.tryParse(date);
      if (d != null) {
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(children: [
            Text('${_weekdayName(d)} ${d.day}/${d.month}',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _isSameDay(d, DateTime.now()) ? AppColors.arenaBlue : AppColors.ink)),
            if (_isSameDay(d, DateTime.now())) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: AppColors.arenaBlue, borderRadius: BorderRadius.circular(8)),
                child: const Text('TODAY', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
              ),
            ],
          ]),
        ));
      }
      for (final s in list) {
        items.add(_card(s, canManage));
      }
    });
    return ListView(padding: const EdgeInsets.only(bottom: 90), children: items);
  }

  // ─────────────────────────── CARD ───────────────────────────
  Widget _card(Shoot s, bool canManage) {
    final c = _parse(s.brandColor);
    final time = _ampm(s.startTime);
    final firsts = s.team.map((m) => m.name.trim().split(' ').first).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: c, width: 4)),
        boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () =>
              ShootDetailSheet.show(context, shoot: s, canManage: canManage),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(s.brandName ?? s.title,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                              decoration: s.isCancelled ? TextDecoration.lineThrough : null)),
                    ),
                    if (time.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                        child: Text(time, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
                      ),
                  ],
                ),
                if ((s.brandName ?? '') != s.title && s.title.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(s.title, style: const TextStyle(fontSize: 12.5, color: AppColors.ink2)),
                ],
                if (s.locationLabel != null) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.place_outlined, size: 14, color: AppColors.ink3),
                    const SizedBox(width: 4),
                    Expanded(child: Text(s.locationLabel!, style: const TextStyle(fontSize: 12.5, color: AppColors.ink2))),
                  ]),
                ],
                if (firsts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: s.team.map((m) {
                      final lead = m.id == s.leadId;
                      final first = m.name.trim().split(' ').first;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                        child: Text(lead ? '★ $first' : first,
                            style: const TextStyle(fontSize: 11, color: AppColors.ink2, fontWeight: FontWeight.w600)),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _weekdayName(DateTime d) {
    const n = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return n[d.weekday];
  }
}

/// Calendar / List segmented toggle in the app bar.
class _Segment extends StatelessWidget {
  final bool calendar;
  final ValueChanged<bool> onChanged;
  const _Segment({required this.calendar, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool active, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active ? AppColors.arenaBlue : Colors.white)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(children: [
        seg('Calendar', calendar, () => onChanged(true)),
        seg('List', !calendar, () => onChanged(false)),
      ]),
    );
  }
}
