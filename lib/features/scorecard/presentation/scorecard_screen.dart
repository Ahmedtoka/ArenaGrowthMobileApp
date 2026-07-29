import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `intl` also exports a `TextDirection` (LTR/RTL) that clashes with Flutter's
// (ltr/rtl). Hide it so `TextDirection.rtl` resolves to the Flutter one.
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/utils/text_direction_util.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/status_pill.dart';
import 'scorecard_providers.dart';

/// "My scorecard" — the employee's own monthly points, rank, pay and stats.
class ScorecardScreen extends ConsumerWidget {
  const ScorecardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(scorecardProvider);
    final (year, month) = ref.watch(scorecardMonthProvider);

    return Scaffold(
      backgroundColor: AppColors.appBg,
      appBar: AppBar(title: const Text('My scorecard')),
      body: Column(
        children: [
          _MonthBar(year: year, month: month),
          const Divider(height: 1),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AppErrorState(
                text: 'Could not load data',
                onRetry: () => ref.invalidate(scorecardProvider),
              ),
              data: (d) => RefreshIndicator(
                onRefresh: () async => ref.refresh(scorecardProvider.future),
                child: _Body(data: d),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthBar extends ConsumerWidget {
  final int year, month;
  const _MonthBar({required this.year, required this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = DateFormat.yMMMM('ar').format(DateTime(year, month));
    void shift(int delta) {
      final d = DateTime(year, month + delta);
      ref.read(scorecardMonthProvider.notifier).state = (d.year, d.month);
    }

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // App is forced LTR → previous = left arrow, next = right arrow.
          IconButton(onPressed: () => shift(-1), icon: const Icon(Icons.chevron_left)),
          SizedBox(width: 150, child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
          IconButton(onPressed: () => shift(1), icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Map<String, dynamic> data;
  const _Body({required this.data});

  num _n(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);

  @override
  Widget build(BuildContext context) {
    final points = (data['points'] as Map?)?.cast<String, dynamic>() ?? {};
    final pay = (data['payslip'] as Map?)?.cast<String, dynamic>();
    final att = (data['attendance'] as Map?)?.cast<String, dynamic>() ?? {};
    final tasks = (data['tasks'] as Map?)?.cast<String, dynamic>() ?? {};
    final rating = (data['rating'] as Map?)?.cast<String, dynamic>() ?? {};
    final breakdown = (points['breakdown'] as List?) ?? [];
    final pv = _n(points['point_value']);
    final compliance = (data['compliance'] as Map?)?.cast<String, dynamic>() ?? {};
    final compScore = _n(compliance['score']);
    final compBreakdown = (compliance['breakdown'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── Points hero ──────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.arenaBlue, AppColors.arenaBlueDark]),
            borderRadius: AppRadius.rLg,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Net points', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  if (points['rank'] != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: AppRadius.rLg),
                      child: Text('🏆 Rank #${points['rank']} / ${points['total_people']}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),),
                    ),
                ],
              ),
              AppSpacing.vXs,
              Text('${_n(points['net'])}', style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold)),
              if (pv > 0)
                Text('≈ ${NumberFormat('#,##0').format(_n(points['money']))} EGP', style: const TextStyle(color: Colors.white, fontSize: 16)),
              AppSpacing.vSm,
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Chip(label: 'Positive', value: '+${_n(points['positive'])}', color: Colors.white),
                  const SizedBox(width: 10),
                  _Chip(label: 'Negative', value: '${_n(points['negative'])}', color: Colors.white),
                ],
              ),
            ],
          ),
        ),
        AppSpacing.vMd,

        // ── Payslip ─────────────────────────────────────────
        _Card(
          title: 'Salary',
          icon: Icons.payments_outlined,
          child: pay == null
              ? const Text('Payroll not generated for this month yet', style: TextStyle(color: AppColors.ink3, fontSize: 13))
              : Column(
                  children: [
                    _row('Base', _n(pay['base']), AppColors.ink),
                    _row('− Absence deduction', _n(pay['absence_deduction']), AppColors.arenaRed, neg: true),
                    _row('− Shortfall deduction', _n(pay['shortfall_deduction']), AppColors.arenaRed, neg: true),
                    _row('+ Overtime', _n(pay['overtime_pay']), AppColors.greenBorder),
                    _row('${_n(pay['points_bonus']) >= 0 ? '+' : '−'} Points bonus', (_n(pay['points_bonus'])).abs(), _n(pay['points_bonus']) >= 0 ? AppColors.greenBorder : AppColors.arenaRed),
                    const Divider(),
                    _row('Net', _n(pay['net']), AppColors.arenaBlue, bold: true),
                    if (pay['finalized'] == true)
                      const Padding(padding: EdgeInsets.only(top: 6), child: Text('🔒 Approved', style: TextStyle(color: AppColors.greenBorder, fontSize: 12))),
                  ],
                ),
        ),
        AppSpacing.vMd,

        // ── Quick stats ─────────────────────────────────────
        Row(
          children: [
            Expanded(child: _Stat(label: 'Present', value: '${_n(att['present_days'])}', sub: 'Absent ${_n(att['absent_days'])}')),
            const SizedBox(width: 10),
            Expanded(child: _Stat(label: 'Net hours', value: '${_n(att['net_hours'])}', sub: 'Overtime +${_n(att['overtime_hours'])}')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _Stat(label: 'Tasks', value: '${_n(tasks['completed'])}', sub: tasks['on_time_pct'] != null ? 'On time ${tasks['on_time_pct']}%' : '—')),
            const SizedBox(width: 10),
            Expanded(child: _Stat(label: 'Rating', value: _n(rating['count']) > 0 ? '${_n(rating['avg'])}★' : '—', sub: '${_n(rating['count'])} ratings')),
          ],
        ),
        AppSpacing.vMd,

        // ── Points breakdown ────────────────────────────────
        if (breakdown.isNotEmpty)
          _Card(
            title: 'Points breakdown',
            icon: Icons.list_alt,
            child: Column(
              children: [
                for (final b in breakdown)
                  InkWell(
                    onTap: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: AppColors.surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.sheetTop,
                      ),
                      builder: (_) => _PointDetailSheet(
                        source: '${b['source'] ?? ''}',
                        label: '${b['label']}',
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(child: Text('${b['label']}  ×${b['count']}', style: const TextStyle(fontSize: 13, color: AppColors.ink2))),
                          Text('${_n(b['points']) >= 0 ? '+' : ''}${_n(b['points'])}',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _n(b['points']) >= 0 ? AppColors.greenBorder : AppColors.arenaRed),),
                          AppSpacing.hXs,
                          const Icon(Icons.chevron_right, size: 16, color: AppColors.ink3),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

        // ── System-usage compliance meter (separate, no money) ──
        AppSpacing.vMd,
        _Card(
          title: 'System usage compliance',
          icon: Icons.verified_user_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${compScore.toInt()}', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _compColor(compScore))),
                  const Text(' / 100', style: TextStyle(color: AppColors.ink3, fontSize: 13)),
                  const Spacer(),
                  Text('${_n(compliance['violations']).toInt()} violations', style: const TextStyle(fontSize: 12, color: AppColors.ink3)),
                ],
              ),
              AppSpacing.vSm,
              ClipRRect(
                borderRadius: AppRadius.rXs,
                child: LinearProgressIndicator(
                  value: (compScore / 100).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  backgroundColor: const Color(0xFFEDEDED),
                  valueColor: AlwaysStoppedAnimation(_compColor(compScore)),
                ),
              ),
              if (compBreakdown.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('No violations — full compliance 👏', style: TextStyle(fontSize: 12.5, color: AppColors.greenBorder)),
                )
              else ...[
                AppSpacing.vSm,
                for (final b in compBreakdown)
                  InkWell(
                    onTap: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: AppColors.surface,
                      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
                      builder: (_) => _PointDetailSheet(source: '${b['source'] ?? ''}', label: '${b['label']}'),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        Expanded(child: Text('${b['label']}  ×${b['count']}', style: const TextStyle(fontSize: 12.5, color: AppColors.ink2))),
                        Text('${_n(b['points'])}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.arenaRed)),
                        AppSpacing.hXs,
                        const Icon(Icons.chevron_right, size: 15, color: AppColors.ink3),
                      ],),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Color _compColor(num s) => s >= 85 ? AppColors.greenBorder : (s >= 60 ? const Color(0xFFB45309) : AppColors.arenaRed);

  Widget _row(String label, num value, Color color, {bool bold = false, bool neg = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: bold ? 15 : 13, color: bold ? AppColors.ink : AppColors.ink2, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(NumberFormat('#,##0').format(value),
              style: TextStyle(fontSize: bold ? 17 : 13, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color),),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Chip({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
      Text(label, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11)),
    ],);
  }
}

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _Card({required this.title, required this.icon, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: AppColors.arenaBlue),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ],),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value, sub;
  const _Stat({required this.label, required this.value, required this.sub});
  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      border: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.ink3, fontSize: 11.5)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.arenaBlue)),
          Text(sub, style: const TextStyle(color: AppColors.ink3, fontSize: 11)),
        ],
      ),
    );
  }
}

/// Bottom sheet that explains WHY the employee earned a points source — the
/// actual records (task name + open/close time, or attendance day + check-in/out).
class _PointDetailSheet extends ConsumerStatefulWidget {
  final String source;
  final String label;
  const _PointDetailSheet({required this.source, required this.label});

  @override
  ConsumerState<_PointDetailSheet> createState() => _PointDetailSheetState();
}

class _PointDetailSheetState extends ConsumerState<_PointDetailSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (year, month) = ref.read(scorecardMonthProvider);
      final repo = ref.read(scorecardRepositoryProvider);
      final d = await repo.fetchDetail(source: widget.source, year: year, month: month);
      if (mounted) setState(() { _data = d; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Could not load details'; _loading = false; });
    }
  }

  String _t(dynamic iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse('$iso')?.toLocal();
    return dt == null ? '—' : DateFormat('d MMM · h:mm a', 'en').format(dt);
  }

  String _d(dynamic iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse('$iso');
    return dt == null ? '$iso' : DateFormat('EEEE d MMM', 'en').format(dt);
  }

  Widget _pts(dynamic p) {
    final n = (p is num) ? p : (num.tryParse('$p') ?? 0);
    return Text('${n >= 0 ? '+' : ''}$n',
        style: TextStyle(fontWeight: FontWeight.w800, color: n >= 0 ? AppColors.greenBorder : AppColors.arenaRed),);
  }

  @override
  Widget build(BuildContext context) {
    final cat = _data?['category'] as String?;
    final rows = (_data?['rows'] as List?) ?? [];
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(children: [
                const Icon(Icons.bolt, color: AppColors.arenaBlue, size: 20),
                AppSpacing.hSm,
                Expanded(child: Text('Why you earned: ${widget.label}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              ],),
            ),
            const Divider(height: 1),
            if (_loading)
              const Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator())
            else if (_error != null)
              Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: AppColors.ink3)))
            else if (rows.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('No details for this month.', style: TextStyle(color: AppColors.ink3)))
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 22),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (_, i) {
                    final r = (rows[i] as Map).cast<String, dynamic>();
                    if (cat == 'task') return _taskRow(r);
                    if (cat == 'attendance') return _attRow(r);
                    return _genericRow(r);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _taskRow(Map<String, dynamic> r) {
    final onTime = r['on_time'];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${r['title'] ?? '—'}',
            textDirection: detectBidiDirection('${r['title'] ?? ''}'),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),),
        const SizedBox(height: 3),
        Text('Opened: ${_t(r['opened_at'])}', style: const TextStyle(fontSize: 11.5, color: AppColors.ink3)),
        Text('Closed: ${_t(r['completed_at'])}', style: const TextStyle(fontSize: 11.5, color: AppColors.ink3)),
        if (onTime != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: StatusPill(
              onTime == true ? 'On time' : 'Late',
              color: onTime == true ? AppColors.success : AppColors.arenaRed,
            ),
          ),
      ],),),
      _pts(r['points']),
    ],);
  }

  Widget _attRow(Map<String, dynamic> r) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_d(r['date']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        const SizedBox(height: 3),
        Text('In: ${_t(r['check_in'])}   →   Out: ${_t(r['check_out'])}', style: const TextStyle(fontSize: 11.5, color: AppColors.ink3)),
        if (r['hours'] != null) Text('Total: ${r['hours']} h', style: const TextStyle(fontSize: 11.5, color: AppColors.ink3)),
      ],),),
      _pts(r['points']),
    ],);
  }

  Widget _genericRow(Map<String, dynamic> r) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${r['note'] ?? '—'}', style: const TextStyle(fontSize: 13)),
        Text(_t(r['occurred_at']), style: const TextStyle(fontSize: 11, color: AppColors.ink3)),
      ],),),
      _pts(r['points']),
    ],);
  }
}
