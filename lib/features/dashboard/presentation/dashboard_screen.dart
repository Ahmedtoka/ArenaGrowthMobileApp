import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/text_direction_util.dart';
import '../../../core/widgets/user_avatar.dart';
import 'dashboard_providers.dart';

/// Read-only, role-aware dashboard.
///
///   - owner              → people + brands + tasks + activity, all data
///   - account_manager    → their brands
///   - department_manager → their department
///   - employee           → their own tasks
///
/// A time filter (today / week / 15 days / month / custom range) drives the
/// "came in" funnel; the attention strip + totals are act-now and ignore it.
class DashboardScreen extends ConsumerWidget {
  /// When embedded as a home-shell TAB, we drop our own Scaffold/AppBar so the
  /// shell's shared header (centered title + quick actions) is the only one.
  final bool embedded;
  const DashboardScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardSummaryProvider);

    final content = Column(
      children: [
        const _FilterBar(),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorView(
              onRetry: () => ref.invalidate(dashboardSummaryProvider),
            ),
            data: (d) => RefreshIndicator(
              onRefresh: () async {
                await ref.refresh(dashboardSummaryProvider.future);
              },
              child: _DashboardBody(data: d),
            ),
          ),
        ),
      ],
    );

    if (embedded) return content;

    return Scaffold(
      backgroundColor: AppColors.appBg,
      appBar: AppBar(title: const Text('Dashboard')),
      body: content,
    );
  }
}

// ───────────────────────── filter bar ─────────────────────────

class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  static const _quick = [
    ('today', 'Today'),
    ('week', 'Week'),
    ('half_month', '15 days'),
    ('month', 'Month'),
    ('30d', '30 days'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(dashboardPeriodProvider);
    final range = ref.watch(dashboardRangeProvider);
    final custom = range != null;

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        children: [
          for (final q in _quick)
            _Chip(
              label: q.$2,
              active: !custom && period == q.$1,
              onTap: () {
                ref.read(dashboardRangeProvider.notifier).state = null;
                ref.read(dashboardPeriodProvider.notifier).state = q.$1;
              },
            ),
          _Chip(
            label: custom ? _rangeLabel(range) : 'Custom',
            icon: Icons.date_range,
            active: custom,
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 2),
                lastDate: now,
                initialDateRange: range,
              );
              if (picked != null) {
                ref.read(dashboardRangeProvider.notifier).state = picked;
              }
            },
          ),
        ],
      ),
    );
  }

  String _rangeLabel(DateTimeRange r) {
    String d(DateTime x) => '${x.day}/${x.month}';
    return '${d(r.start)} – ${d(r.end)}';
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: active ? AppColors.arenaBlue : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: active ? AppColors.arenaBlue : AppColors.border,),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 15,
                      color: active ? Colors.white : AppColors.ink2,),
                  const SizedBox(width: 5),
                ],
                Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : AppColors.ink2,
                    ),),
              ],
            ),
          ),
        ),
      );
}

// ───────────────────────── body ─────────────────────────

class _DashboardBody extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DashboardBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final attention = _map(data['attention']);
    final funnel = _map(data['funnel']);
    final funnelLists = _map(data['funnel_lists']);
    final totals = _map(data['totals']);
    final myActivity = _list(data['my_activity']);
    final brands = _map(data['brands']);
    final peopleRaw = data['people'];
    final people = peopleRaw is Map ? peopleRaw.cast<String, dynamic>() : null;
    final activityRaw = data['activity'];
    final activity = activityRaw is Map ? activityRaw.cast<String, dynamic>() : null;
    final top = _list(data['top_performers']);
    final online = _list(data['online_users']);
    final role = (data['role'] as String?) ?? '';
    final attnLists = _map(attention['lists']);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        // ── HERO: needs attention ───────────────────────
        const Row(
          children: [
            Icon(Icons.bolt, size: 18, color: AppColors.arenaRed),
            SizedBox(width: 6),
            _SectionTitle('Needs your attention'),
          ],
        ),
        const _Hint('Act on these first — independent of the date filter.'),
        const SizedBox(height: 8),
        _MiniRow(children: [
          _AttnTile(
            label: 'Overdue',
            value: _int(attention['overdue']),
            color: AppColors.arenaRed,
            icon: Icons.warning_amber_rounded,
            onTap: () => _openTaskList(
                context, 'Overdue', _list(attnLists['overdue']),),
          ),
          _AttnTile(
            label: 'Awaiting',
            value: _int(attention['awaiting']),
            color: AppColors.warning,
            icon: Icons.hourglass_bottom,
            onTap: () => _openTaskList(
                context, 'Awaiting clarification', _list(attnLists['awaiting']),),
          ),
          _AttnTile(
            label: 'New to me',
            value: _int(attention['new_to_me']),
            color: AppColors.arenaBlue,
            icon: Icons.fiber_new,
            onTap: () => _openTaskList(
                context, 'New — not opened', _list(attnLists['new_to_me']),),
          ),
        ],),

        // ── Flow in this period (by when it happened) ───
        const SizedBox(height: 22),
        const _SectionTitle('In this period'),
        const _Hint('Counted by time: arrivals by creation date, '
            'done by completion date.'),
        const SizedBox(height: 8),
        _FunnelCard(rows: const [
          _FunnelSpec('came_in', 'Came in', 'Created inside the selected window',
              Color(0xFF2235FF), Icons.call_received,),
          _FunnelSpec('done', 'Done', 'Completed inside the window (by finish date)',
              Color(0xFF10B981), Icons.check_circle_outline,),
        ], funnel: funnel, lists: funnelLists,),

        // ── Live pipeline (now) ─────────────────────────
        const SizedBox(height: 22),
        const _SectionTitle('Pipeline right now'),
        const _Hint('Your live backlog — independent of the date filter.'),
        const SizedBox(height: 8),
        _MiniRow(children: [
          _MiniStat('This month', _int(totals['this_month'])),
          _MiniStat('All open now', _int(totals['all_open'])),
          if (activity != null)
            _MiniStat('Msgs today', _int(activity['messages_today'])),
        ],),
        const SizedBox(height: 12),
        // "New" first, each with a one-line description.
        _FunnelCard(rows: const [
          _FunnelSpec('new', 'New', 'Assigned, nobody opened it yet',
              Color(0xFF3B82F6), Icons.fiber_new,),
          _FunnelSpec('opened_not_started', 'Opened · not started',
              'Opened but work hasn\'t begun', Color(0xFF8B5CF6),
              Icons.visibility_outlined,),
          _FunnelSpec('in_progress', 'In progress', 'Being worked on right now',
              Color(0xFF2235FF), Icons.bolt_outlined,),
          _FunnelSpec('awaiting', 'Awaiting', 'Blocked — waiting on a reply',
              Color(0xFFF59E0B), Icons.hourglass_bottom,),
          _FunnelSpec('overdue', 'Overdue', 'Past its due date, still open',
              Color(0xFFE63A2D), Icons.warning_amber_rounded,),
        ], funnel: funnel, lists: funnelLists,),

        // ── Latest about me ─────────────────────────────
        if (myActivity.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Row(
            children: [
              Icon(Icons.update, size: 18, color: AppColors.arenaBlue),
              SizedBox(width: 6),
              _SectionTitle('Latest 5 task updates'),
            ],
          ),
          const _Hint('Your most recently changed tasks.'),
          const SizedBox(height: 8),
          for (final t in myActivity.take(5))
            _ActivityRow(task: (t as Map).cast<String, dynamic>()),
        ],

        // ── Client by client ────────────────────────────
        if (_list(brands['breakdown']).isNotEmpty) ...[
          const SizedBox(height: 22),
          const _SectionTitle('Client by client'),
          const _Hint('Open / late / done-today per brand.'),
          const SizedBox(height: 6),
          _BrandsTotals(brands: brands),
          const SizedBox(height: 8),
          for (final b in _list(brands['breakdown']))
            _BrandRow(brand: (b as Map).cast<String, dynamic>()),
        ],

        // ── People (owner only) ─────────────────────────
        if (people != null) ...[
          const SizedBox(height: 22),
          const _SectionTitle('Team'),
          const SizedBox(height: 8),
          _MiniRow(children: [
            _MiniStat('People', _int(people['total'])),
            _MiniStat('Online', _int(people['online']),
                color: AppColors.success,),
            _MiniStat('Offline', _int(people['offline'])),
          ],),
          if (online.isNotEmpty) ...[
            const SizedBox(height: 12),
            _OnlineStrip(users: online),
          ],
        ],

        // ── Top performers ──────────────────────────────
        if (top.isNotEmpty) ...[
          const SizedBox(height: 22),
          const _SectionTitle('Top performers this week'),
          const SizedBox(height: 8),
          for (final u in top)
            _PerformerRow(user: (u as Map).cast<String, dynamic>()),
        ],

        const SizedBox(height: 16),
        Center(
          child: Text('Read-only · ${_roleLabel(role)}',
              style: const TextStyle(fontSize: 11, color: AppColors.ink3),),
        ),
      ],
    );
  }
}

// ───────────────────────── pieces ─────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink,),);
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(text,
            style: const TextStyle(fontSize: 11.5, color: AppColors.ink3),),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(14)});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

/// Attention tile — bigger, tinted, tappable.
class _AttnTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _AttnTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 6),
              Text('$value',
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800, color: color,),),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: AppColors.ink2),),
            ],
          ),
        ),
      );
}

class _MiniRow extends StatelessWidget {
  final List<Widget> children;
  const _MiniRow({required this.children});
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              Expanded(child: children[i]),
              if (i != children.length - 1) const SizedBox(width: 10),
            ],
          ],
        ),
      );
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int value;
  final Color? color;
  const _MiniStat(this.label, this.value, {this.color});
  @override
  Widget build(BuildContext context) => _Card(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color ?? AppColors.ink,),),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: AppColors.ink3),),
          ],
        ),
      );
}

class _FunnelSpec {
  final String key;
  final String label;
  final String desc;
  final Color color;
  final IconData icon;
  const _FunnelSpec(this.key, this.label, this.desc, this.color, this.icon);
}

class _FunnelCard extends StatelessWidget {
  final List<_FunnelSpec> rows;
  final Map<String, dynamic> funnel;
  final Map<String, dynamic> lists;
  const _FunnelCard({
    required this.rows,
    required this.funnel,
    required this.lists,
  });
  @override
  Widget build(BuildContext context) => _Card(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i != 0) const Divider(height: 1),
              _FunnelRow(
                spec: rows[i],
                value: _int(funnel[rows[i].key]),
                onTap: () => _openTaskList(
                    context, rows[i].label, _list(lists[rows[i].key]),),
              ),
            ],
          ],
        ),
      );
}

class _FunnelRow extends StatelessWidget {
  final _FunnelSpec spec;
  final int value;
  final VoidCallback onTap;
  const _FunnelRow({
    required this.spec,
    required this.value,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: spec.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(spec.icon, size: 18, color: spec.color),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(spec.label,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700,),),
                    Text(spec.desc,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.ink3,),),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('$value',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: spec.color,),),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.ink3),
            ],
          ),
        ),
      );
}

class _BrandsTotals extends StatelessWidget {
  final Map<String, dynamic> brands;
  const _BrandsTotals({required this.brands});
  @override
  Widget build(BuildContext context) => Text(
        '${_int(brands['total'])} clients · '
        '${_int(brands['with_active_tasks'])} active · '
        '${_int(brands['idle'])} idle',
        style: const TextStyle(fontSize: 12, color: AppColors.ink3),
      );
}

class _BrandRow extends StatelessWidget {
  final Map<String, dynamic> brand;
  const _BrandRow({required this.brand});
  @override
  Widget build(BuildContext context) {
    final overdue = _int(brand['overdue_tasks']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _Card(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((brand['name'] ?? '—') as String,
                      textDirection:
                          detectBidiDirection((brand['name'] ?? '') as String),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600,),),
                  if (brand['account_manager'] != null)
                    Text('AM: ${brand['account_manager']}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.ink3,),),
                ],
              ),
            ),
            _Pill('${_int(brand['open_tasks'])} open', AppColors.arenaBlue),
            if (overdue > 0) ...[
              const SizedBox(width: 6),
              _Pill('$overdue late', AppColors.arenaRed),
            ],
            if (_int(brand['done_today']) > 0) ...[
              const SizedBox(width: 6),
              _Pill('${_int(brand['done_today'])} ✓', AppColors.success),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color,),),
      );
}

class _OnlineStrip extends StatelessWidget {
  final List users;
  const _OnlineStrip({required this.users});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 64,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final u = (users[i] as Map).cast<String, dynamic>();
            return SizedBox(
              width: 54,
              child: Column(
                children: [
                  Stack(
                    children: [
                      UserAvatar(
                        name: (u['name'] ?? '') as String,
                        avatarUrl: u['avatar_url'] as String?,
                        size: 40,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    ((u['name'] ?? '') as String).split(' ').first,
                    textDirection:
                        detectBidiDirection((u['name'] ?? '') as String),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppColors.ink2),
                  ),
                ],
              ),
            );
          },
        ),
      );
}

class _PerformerRow extends StatelessWidget {
  final Map<String, dynamic> user;
  const _PerformerRow({required this.user});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _Card(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              UserAvatar(
                name: (user['name'] ?? '') as String,
                avatarUrl: user['avatar_url'] as String?,
                size: 32,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text((user['name'] ?? '—') as String,
                    textDirection:
                        detectBidiDirection((user['name'] ?? '') as String),
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600,),),
              ),
              _Pill('${_int(user['done_this_week'])} done', AppColors.success),
            ],
          ),
        ),
      );
}

/// One "about me" task — status chip + tap-through to the task.
class _ActivityRow extends StatelessWidget {
  final Map<String, dynamic> task;
  const _ActivityRow({required this.task});
  @override
  Widget build(BuildContext context) {
    final mineAs = (task['mine_as'] ?? '') as String;
    final status = (task['status'] ?? '') as String;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openTask(context, task['id']),
        child: _Card(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 34,
                decoration: BoxDecoration(
                  color: _statusColor(status),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((task['title'] ?? '—') as String,
                        textDirection:
                            detectBidiDirection((task['title'] ?? '') as String),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600,),),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          mineAs == 'assignee'
                              ? 'Assigned to me'
                              : 'Created by me',
                          style: const TextStyle(
                              fontSize: 10.5, color: AppColors.ink3,),
                        ),
                        if (task['brand'] != null) ...[
                          const Text('  ·  ',
                              style: TextStyle(
                                  fontSize: 10.5, color: AppColors.ink3,),),
                          Flexible(
                            child: Text(task['brand'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 10.5, color: AppColors.ink3,),),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Pill(_statusLabel(status), _statusColor(status)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: AppColors.ink3),
            const SizedBox(height: 12),
            const Text('Could not load the dashboard.',
                style: TextStyle(color: AppColors.ink2),),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}

// ───────────────────────── task-list sheet ─────────────────────────

void _openTask(BuildContext context, Object? id) {
  if (id == null) return;
  context.push('/tasks/$id');
}

void _openTaskList(BuildContext context, String title, List items) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (ctx, scroll) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700,),),
                const Spacer(),
                Text('${items.length}',
                    style: const TextStyle(fontSize: 13, color: AppColors.ink3),),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nothing here 🎉',
                          style: TextStyle(color: AppColors.ink3),),
                    ),
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final t = (items[i] as Map).cast<String, dynamic>();
                      return _TaskListRow(
                        task: t,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _openTask(context, t['id']);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

class _TaskListRow extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback onTap;
  const _TaskListRow({required this.task, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final status = (task['status'] ?? '') as String;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: _Card(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              _Pill('P${_int(task['priority'])}',
                  _priorityColor('${task['priority']}'),),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((task['title'] ?? '—') as String,
                        textDirection:
                            detectBidiDirection((task['title'] ?? '') as String),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600,),),
                    if (task['brand'] != null || task['assignee'] != null)
                      Text(
                        [
                          if (task['brand'] != null) task['brand'],
                          if (task['assignee'] != null) '→ ${task['assignee']}',
                        ].join('  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.ink3,),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Pill(_statusLabel(status), _statusColor(status)),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── helpers ─────────────────────────

int _int(Object? v) => v is int ? v : int.tryParse('${v ?? 0}') ?? 0;

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

List _list(Object? v) => v is List ? v : const [];

String _statusLabel(String k) => switch (k) {
      'pending' => 'Pending',
      'in_progress' => 'In progress',
      'awaiting_clarification' => 'Awaiting',
      'resumed' => 'Resumed',
      'done' => 'Done',
      'approved' => 'Approved',
      'archived' => 'Archived',
      'cancelled' => 'Cancelled',
      'received' => 'Received',
      _ => k,
    };

Color _statusColor(String k) => switch (k) {
      'pending' => const Color(0xFF9CA3AF),
      'in_progress' => const Color(0xFF3B82F6),
      'awaiting_clarification' => const Color(0xFFF59E0B),
      'resumed' => const Color(0xFF8B5CF6),
      'done' => const Color(0xFF10B981),
      'approved' => const Color(0xFF059669),
      'received' => const Color(0xFF059669),
      _ => const Color(0xFF9CA3AF),
    };

Color _priorityColor(String k) => switch (k) {
      '1' => const Color(0xFF9CA3AF),
      '2' => const Color(0xFF3B82F6),
      '3' => const Color(0xFFF59E0B),
      '4' => const Color(0xFFEA580C),
      '5' || '6' => const Color(0xFFE63A2D),
      _ => AppColors.arenaBlue,
    };

String _roleLabel(String k) => switch (k) {
      'owner' => 'Owner',
      'account_manager' => 'Account Manager',
      'department_manager' => 'Dept. Manager',
      'employee' => 'Employee',
      _ => k,
    };
