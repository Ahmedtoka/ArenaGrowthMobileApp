import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/utils/text_direction_util.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/models/task_model.dart';
import '../../data/repositories/tasks_repository.dart';
import '../controllers/tasks_providers.dart';

class TasksListTab extends ConsumerWidget {
  const TasksListTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(taskTabControllerProvider);
    final tasksAsync = ref.watch(tasksListProvider);

    return Column(
      children: [
        const _TasksHeader(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(tasksListProvider),
            child: tasksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(
                error: e,
                onRetry: () => ref.invalidate(tasksListProvider),
              ),
              data: (result) {
                final tasks = result.tasks;
                if (tasks.isEmpty) {
                  return _EmptyState(label: tab.label);
                }
                return ListView.builder(
                  // Extra bottom inset so the last card clears the two FABs.
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                  itemCount: tasks.length,
                  itemBuilder: (ctx, i) => _TaskCard(task: tasks[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Two-row header: status tabs (with live open-count badges) + Add Task on
/// top, date filters (and, for managers only, employee + brand filters) below.
class _TasksHeader extends ConsumerWidget {
  const _TasksHeader();

  int _badgeFor(TaskTab t, TaskCounts c) => switch (t) {
        TaskTab.newTasks => c.newCount,
        TaskTab.inProgress => c.inProgress,
        TaskTab.waiting => c.waiting,
        TaskTab.delivered => c.delivered,
        TaskTab.done => c.done,
        TaskTab.all => c.all,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(taskTabControllerProvider);
    final range = ref.watch(taskRangeControllerProvider);
    final counts =
        ref.watch(tasksListProvider).valueOrNull?.counts ?? const TaskCounts();
    final user = ref.watch(authControllerProvider).valueOrNull;
    final isManager = (user?.isOwner ?? false) || (user?.isAccountManager ?? false);
    final assignee = ref.watch(taskFilterAssigneeProvider);
    final brand = ref.watch(taskFilterBrandProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Row 1: status tabs (full width; Add Task lives as a FAB) ───
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final t in TaskTab.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _TabChip(
                      label: t.label,
                      selected: t == tab,
                      badge: _badgeFor(t, counts),
                      onTap: () => ref
                          .read(taskTabControllerProvider.notifier)
                          .set(t),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // ── Row 2: date filters (+ manager filters) ────────────────────
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final r in TaskDateRange.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _PillChip(
                      icon: r == TaskDateRange.custom
                          ? Icons.event
                          : Icons.calendar_today,
                      label: r == TaskDateRange.custom
                          ? _customLabel(ref, range)
                          : r.label,
                      selected: r == range,
                      onTap: () async {
                        if (r == TaskDateRange.custom) {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2023),
                            lastDate: DateTime.now()
                                .add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            ref
                                .read(taskCustomRangeControllerProvider.notifier)
                                .set(from: picked.start, to: picked.end);
                            ref
                                .read(taskRangeControllerProvider.notifier)
                                .set(TaskDateRange.custom);
                          }
                        } else {
                          ref
                              .read(taskRangeControllerProvider.notifier)
                              .set(r);
                        }
                      },
                    ),
                  ),
                if (isManager) ...[
                  const _FilterDivider(),
                  _PillChip(
                    icon: Icons.person_outline,
                    label: assignee == null ? 'Employee' : 'Employee ✓',
                    selected: assignee != null,
                    onTap: () => _pickEmployee(context, ref),
                  ),
                  const SizedBox(width: 6),
                  _PillChip(
                    icon: Icons.business_outlined,
                    label: brand == null ? 'Brand' : 'Brand ✓',
                    selected: brand != null,
                    onTap: () => _pickBrand(context, ref),
                  ),
                  if (assignee != null || brand != null) ...[
                    const SizedBox(width: 6),
                    _PillChip(
                      icon: Icons.clear,
                      label: 'Clear',
                      selected: false,
                      onTap: () {
                        ref
                            .read(taskFilterAssigneeProvider.notifier)
                            .set(null);
                        ref.read(taskFilterBrandProvider.notifier).set(null);
                      },
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _customLabel(WidgetRef ref, TaskDateRange range) {
    if (range != TaskDateRange.custom) return 'Custom';
    final w = ref.watch(taskCustomRangeControllerProvider);
    if (w.from == null || w.to == null) return 'Custom';
    String f(DateTime d) => '${d.day}/${d.month}';
    return '${f(w.from!)} – ${f(w.to!)}';
  }

  Future<void> _pickEmployee(BuildContext context, WidgetRef ref) async {
    final employees =
        await ref.read(taskFilterEmployeesProvider.future).catchError(
              (_) => <Map<String, dynamic>>[],
            );
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _PickerSheet(
        title: 'Filter by employee',
        items: [
          const _PickItem(id: null, label: 'All employees'),
          for (final e in employees)
            _PickItem(
              id: e['id'] as int?,
              label: (e['name'] ?? e['full_name'] ?? 'User').toString(),
            ),
        ],
        onPick: (id) =>
            ref.read(taskFilterAssigneeProvider.notifier).set(id),
      ),
    );
  }

  Future<void> _pickBrand(BuildContext context, WidgetRef ref) async {
    final brands = await ref.read(taskFilterBrandsProvider.future).catchError(
          (_) => <Map<String, dynamic>>[],
        );
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _PickerSheet(
        title: 'Filter by brand',
        items: [
          const _PickItem(id: null, label: 'All brands'),
          for (final b in brands)
            _PickItem(
              id: b['id'] as int?,
              label: (b['name'] ?? 'Brand').toString(),
            ),
        ],
        onPick: (id) => ref.read(taskFilterBrandProvider.notifier).set(id),
      ),
    );
  }
}

/// Status tab chip with an optional count badge.
class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;
  const _TabChip({
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.arenaBlue : AppColors.appBg,
      borderRadius: AppRadius.rLg,
      child: InkWell(
        borderRadius: AppRadius.rLg,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.ink2,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (badge > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : AppColors.arenaBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      color: selected ? AppColors.arenaBlue : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small icon + label pill used for date + manager filters.
class _PillChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PillChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.ink2;
    return Material(
      color: selected ? AppColors.arenaBlue : AppColors.appBg,
      borderRadius: AppRadius.rLg,
      child: InkWell(
        borderRadius: AppRadius.rLg,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              AppSpacing.hXs,
              Text(label,
                  style: TextStyle(
                      color: fg,
                      fontSize: 12.5,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterDivider extends StatelessWidget {
  const _FilterDivider();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        color: AppColors.divider,
      );
}

class _PickItem {
  final int? id;
  final String label;
  const _PickItem({required this.id, required this.label});
}

class _PickerSheet extends StatelessWidget {
  final String title;
  final List<_PickItem> items;
  final void Function(int? id) onPick;
  const _PickerSheet({
    required this.title,
    required this.items,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final it = items[i];
                return ListTile(
                  dense: true,
                  title: Text(it.label,
                      textDirection: detectBidiDirection(it.label)),
                  onTap: () {
                    onPick(it.id);
                    Navigator.of(ctx).pop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskModel task;
  const _TaskCard({required this.task});

  static int _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? 0}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final brandColor =
        _parseHexColor(task.brand?.primaryColor) ?? AppColors.arenaBlue;
    final statusSpec = _statusSpec(task.status);
    final prioritySpec = _prioritySpec(task.priority);

    // Deliverables progress (mini bar) — tasks now carry quantified outputs.
    var totQ = 0, totD = 0;
    for (final d in task.deliverables) {
      if (d is Map) {
        totQ += _int(d['qty']);
        totD += _int(d['done']);
      }
    }
    final hasDeliv = totQ > 0;
    final delivPct = hasDeliv ? (totD / totQ).clamp(0.0, 1.0) : 0.0;
    final delivDone = hasDeliv && totD >= totQ;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.rMd,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: task.isOverdue
            ? Border.all(color: AppColors.arenaRed.withValues(alpha: 0.5))
            : null,
      ),
      child: InkWell(
        onTap: () => context.push('/tasks/${task.id}'),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Brand-colour accent stripe.
              Container(width: 4, color: brandColor),
              Expanded(
                child: Padding(
                  padding: AppSpacing.card,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top row: brand badge + priority
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3,),
                            decoration: BoxDecoration(
                              color: brandColor.withValues(alpha: 0.12),
                              borderRadius: AppRadius.rSm,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                      color: brandColor,
                                      shape: BoxShape.circle,),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  task.brand?.name ?? 'No brand',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: brandColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (prioritySpec != null)
                            _PriorityBadge(spec: prioritySpec),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Title
                      Text(
                        task.title,
                        textDirection: detectBidiDirection(task.title),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                          height: 1.35,
                        ),
                      ),

                      // Description
                      if (task.description != null &&
                          task.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            task.description!,
                            textDirection: detectBidiDirection(task.description),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.ink2,
                              height: 1.35,
                            ),
                          ),
                        ),

                      // Deliverables progress (only when the task has any).
                      if (hasDeliv) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 13,
                                color: delivDone
                                    ? AppColors.greenBorder
                                    : AppColors.ink3,),
                            const SizedBox(width: 5),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: delivPct,
                                  minHeight: 5,
                                  backgroundColor: AppColors.border,
                                  valueColor: AlwaysStoppedAnimation(
                                      delivDone
                                          ? AppColors.greenBorder
                                          : AppColors.arenaBlue,),
                                ),
                              ),
                            ),
                            AppSpacing.hSm,
                            Text('$totD/$totQ',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: delivDone
                                        ? AppColors.greenBorder
                                        : AppColors.ink2,),),
                          ],
                        ),
                      ],

                      const SizedBox(height: 10),

                      // Bottom row: status + assignee + due
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _StatusPill(spec: statusSpec),
                          if (task.assignee != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                UserAvatar(
                                    name: task.assignee!.name,
                                    size: 18,
                                    backgroundColor: brandColor,),
                                const SizedBox(width: 5),
                                Text(
                                  task.assignee!.name,
                                  style: const TextStyle(
                                      fontSize: 11.5, color: AppColors.ink2,),
                                ),
                              ],
                            ),
                          if (task.timestamps?.dueAt != null)
                            _IconText(
                              icon: Icons.schedule,
                              text: _dueLabel(task.timestamps!.dueAt!),
                              color:
                                  task.isOverdue ? AppColors.arenaRed : null,
                              bold: task.isOverdue,
                            ),
                          if (task.isOverdue)
                            const _IconText(
                              icon: Icons.warning_amber,
                              text: 'Overdue',
                              color: AppColors.arenaRed,
                              bold: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dueLabel(DateTime d) {
    final local = d.toLocal();
    final now = DateTime.now();
    final diff = local.difference(now);
    if (diff.inDays.abs() < 1 && diff.isNegative == false) {
      return 'Today ${DateFormat('h:mm a').format(local)}';
    }
    if (diff.inDays == 1) return 'Tomorrow ${DateFormat('h:mm a').format(local)}';
    return DateFormat('d/M/y · h:mm a').format(local);
  }

  Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final value = int.tryParse(h, radix: 16);
    return value == null ? null : Color(value);
  }

  _StatusSpec _statusSpec(String s) => switch (s) {
        TaskStatus.pending => const _StatusSpec(
            'Pending', Color(0xFFEEF2F7), AppColors.ink2,),
        TaskStatus.inProgress => const _StatusSpec(
            'In Progress', AppColors.arenaBlueLight, AppColors.arenaBlue,),
        TaskStatus.done => const _StatusSpec(
            'Done', AppColors.greenBg, AppColors.greenBorder,),
        TaskStatus.approved => const _StatusSpec(
            'Approved', AppColors.greenBg, AppColors.greenBorder,),
        'received' => const _StatusSpec(
            'Received', Color(0xFFEDE9FE), Color(0xFF6D28D9),),
        TaskStatus.awaitingClarification => const _StatusSpec(
            'Awaiting Clarification', Color(0xFFFEF3C7), Color(0xFFB45309),),
        TaskStatus.resumed => const _StatusSpec(
            'Resumed', AppColors.arenaBlueLight, AppColors.arenaBlue,),
        TaskStatus.archived =>
          const _StatusSpec('Archived', Color(0xFFEEF2F7), AppColors.ink3),
        TaskStatus.cancelled =>
          const _StatusSpec('Cancelled', AppColors.redBg, AppColors.arenaRed),
        _ => _StatusSpec(s, const Color(0xFFEEF2F7), AppColors.ink2),
      };

  _PrioritySpec? _prioritySpec(String? p) => switch (p) {
        'urgent' => const _PrioritySpec('Urgent', AppColors.arenaRed),
        'high' => const _PrioritySpec('High', AppColors.orangeBorder),
        'low' => const _PrioritySpec('Low', AppColors.ink3),
        _ => null,
      };
}

class _StatusSpec {
  final String label;
  final Color bg;
  final Color fg;
  const _StatusSpec(this.label, this.bg, this.fg);
}

class _PrioritySpec {
  final String label;
  final Color color;
  const _PrioritySpec(this.label, this.color);
}

class _StatusPill extends StatelessWidget {
  final _StatusSpec spec;
  const _StatusPill({required this.spec});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: spec.bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          spec.label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: spec.fg,),
        ),
      );
}

class _PriorityBadge extends StatelessWidget {
  final _PrioritySpec spec;
  const _PriorityBadge({required this.spec});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: spec.color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.priority_high, color: Colors.white, size: 11),
            const SizedBox(width: 2),
            Text(
              spec.label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
}

class _IconText extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  final bool bold;
  const _IconText({
    required this.icon,
    required this.text,
    this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.ink3;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            color: c,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String label;
  const _EmptyState({required this.label});

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          const SizedBox(height: 100),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.task_alt, size: 56, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    'No tasks in "$label"',
                    style: const TextStyle(color: AppColors.ink3),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          const SizedBox(height: 100),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text(
                  'Could not load tasks',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      );
}
