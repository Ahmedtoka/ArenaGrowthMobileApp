import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/utils/text_direction_util.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_pill.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../data/leave_models.dart';
import 'leave_providers.dart';

class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key});

  bool _isManager(WidgetRef ref) {
    final u = ref.watch(authControllerProvider).valueOrNull;
    return (u?.isOwner ?? false) ||
        (u?.isAccountManager ?? false) ||
        (u?.teamRole == 'department_manager');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManager = _isManager(ref);
    final mine = ref.watch(myLeavesProvider);

    return Scaffold(
      backgroundColor: AppColors.appBg,
      appBar: AppBar(
        title: const Text('Leave'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(myLeavesProvider);
              ref.invalidate(pendingLeavesProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.arenaBlue,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Request', style: TextStyle(color: Colors.white)),
        onPressed: () async {
          final ok = await _RequestSheet.show(context, ref);
          if (ok == true) ref.invalidate(myLeavesProvider);
        },
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myLeavesProvider);
          ref.invalidate(pendingLeavesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            mine.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const AppErrorState(
                  text: 'Couldn’t load your leave. Pull to retry.',),
              data: (m) => _BalanceCard(balance: m.balance),
            ),
            if (isManager) ...[
              AppSpacing.vLg,
              const SectionHeader('Pending approvals', color: AppColors.warning),
              _PendingApprovals(),
            ],
            AppSpacing.vLg,
            const SectionHeader('My requests', color: AppColors.arenaBlue),
            mine.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (m) => m.requests.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.beach_access_outlined,
                      text: 'No leave requests yet.',)
                  : Column(
                      children: m.requests
                          .map((r) => _MyRequestRow(req: r))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Balance ──────────────────────────────────────────────────────────
class _BalanceCard extends StatelessWidget {
  final LeaveBalance balance;
  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final pct = balance.allocation > 0
        ? (balance.used / balance.allocation).clamp(0.0, 1.0)
        : 0.0;
    return AppCard(
      padding: AppSpacing.page,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Leave balance · ${balance.year}',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink2,),),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('Remaining', balance.remaining, AppColors.arenaBlue, big: true),
              _stat('Used', balance.used, const Color(0xFF16A34A)),
              _stat('Pending', balance.pending, const Color(0xFFF59E0B)),
              _stat('Total', balance.allocation, AppColors.ink3),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation(AppColors.arenaBlue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, int value, Color color, {bool big = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value',
              style: TextStyle(
                  fontSize: big ? 26 : 20,
                  fontWeight: FontWeight.w800,
                  color: color,),),
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppColors.ink3),),
        ],
      ),
    );
  }
}

// ── Pending approvals (managers) ─────────────────────────────────────
class _PendingApprovals extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingLeavesProvider);
    return pending.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) => list.isEmpty
          ? const AppEmptyState(
              icon: Icons.inbox_outlined, text: 'Nothing waiting on you.',)
          : Column(
              children: list
                  .map((r) => _ApprovalRow(req: r))
                  .toList(),
            ),
    );
  }
}

class _ApprovalRow extends ConsumerStatefulWidget {
  final LeaveRequestModel req;
  const _ApprovalRow({required this.req});
  @override
  ConsumerState<_ApprovalRow> createState() => _ApprovalRowState();
}

class _ApprovalRowState extends ConsumerState<_ApprovalRow> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    setState(() => _busy = true);
    final repo = ref.read(leaveRepositoryProvider);
    try {
      if (approve) {
        await repo.approve(widget.req.id);
      } else {
        final note = await _promptNote(context);
        if (note == null) {
          setState(() => _busy = false);
          return;
        }
        await repo.reject(widget.req.id, note: note);
      }
      ref.invalidate(pendingLeavesProvider);
      ref.invalidate(myLeavesProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action failed. Try again.')),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.req;
    return AppCard(
      accent: AppColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.userName ?? 'Employee',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,),),
          const SizedBox(height: 2),
          Text('${_range(r)} · ${r.days} day(s) · ${r.type}',
              style: const TextStyle(fontSize: 12, color: AppColors.ink3),),
          if ((r.reason ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(r.reason!,
                textDirection: detectBidiDirection(r.reason),
                style: const TextStyle(fontSize: 12.5, color: AppColors.ink2),),
          ],
          const SizedBox(height: 10),
          if (_busy)
            const Center(
                child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),),)
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _decide(false),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.arenaRed,),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _decide(true),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── My request row ───────────────────────────────────────────────────
class _MyRequestRow extends ConsumerWidget {
  final LeaveRequestModel req;
  const _MyRequestRow({required this.req});

  Color _statusColor(String s) => switch (s) {
        'approved' => const Color(0xFF16A34A),
        'rejected' => AppColors.arenaRed,
        'cancelled' => AppColors.ink3,
        _ => const Color(0xFFF59E0B),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = _statusColor(req.status);
    return AppCard(
      accent: c,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_range(req)} · ${req.days} day(s)',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700,),),
                const SizedBox(height: 2),
                Text(
                    '${req.type}'
                    '${req.reviewedBy != null ? ' · by ${req.reviewedBy}' : ''}',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.ink3),),
                if ((req.reviewNote ?? '').isNotEmpty)
                  Text(req.reviewNote!,
                      textDirection: detectBidiDirection(req.reviewNote),
                      style:
                          const TextStyle(fontSize: 11.5, color: AppColors.ink3),),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(req.statusLabel, color: c),
          if (req.isPending)
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () async {
                await ref.read(leaveRepositoryProvider).cancel(req.id);
                ref.invalidate(myLeavesProvider);
              },
            ),
        ],
      ),
    );
  }
}

// ── Request sheet ────────────────────────────────────────────────────
class _RequestSheet extends ConsumerStatefulWidget {
  const _RequestSheet();

  static Future<bool?> show(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => const _RequestSheet(),
      );

  @override
  ConsumerState<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends ConsumerState<_RequestSheet> {
  static const _types = ['annual', 'sick', 'unpaid', 'emergency'];
  String _type = 'annual';
  DateTimeRange? _range;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_range == null) {
      setState(() => _error = 'Pick the leave dates.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(leaveRepositoryProvider).request(
            type: _type,
            start: _range!.start,
            end: _range!.end,
            reason: _reason.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() {
        _busy = false;
        _error = 'Could not submit. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('MMM d');
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Request leave',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),),
          const SizedBox(height: 14),
          const Text('Type',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: _types.map((t) {
              final sel = t == _type;
              return ChoiceChip(
                label: Text(t),
                selected: sel,
                onSelected: (_) => setState(() => _type = t),
                selectedColor: AppColors.arenaBlue,
                labelStyle: TextStyle(
                    color: sel ? Colors.white : AppColors.ink2,
                    fontWeight: FontWeight.w600,),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const Text('Dates',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            icon: const Icon(Icons.event, size: 18),
            label: Text(_range == null
                ? 'Pick date range'
                : '${f.format(_range!.start)} – ${f.format(_range!.end)}',),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _range = picked);
            },
          ),
          const SizedBox(height: 14),
          const Text('Reason (optional)',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),),
          const SizedBox(height: 6),
          TextField(
            controller: _reason,
            maxLines: 2,
            textDirection: detectBidiDirection(_reason.text),
            decoration: InputDecoration(
              hintText: 'Add a note for your manager…',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: AppColors.arenaRed, fontSize: 12),),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.arenaBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white,),)
                  : const Text('Submit request'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── shared bits ──────────────────────────────────────────────────────
String _range(LeaveRequestModel r) {
  final f = DateFormat('MMM d');
  if (r.start == null) return '';
  if (r.end == null || r.start!.isAtSameMomentAs(r.end!)) {
    return f.format(r.start!);
  }
  return '${f.format(r.start!)} – ${f.format(r.end!)}';
}

Future<String?> _promptNote(BuildContext context) async {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Reject leave'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Reason (optional)'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'),),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Reject'),),
      ],
    ),
  );
}
