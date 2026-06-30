import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/text_direction_util.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/models/task_model.dart';
import '../controllers/tasks_providers.dart';

class TasksListTab extends ConsumerWidget {
  const TasksListTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(tasksScopeControllerProvider);
    final tasksAsync = ref.watch(tasksListProvider);

    return Column(
      children: [
        _ScopeChips(
          scope: scope,
          onChange: (s) =>
              ref.read(tasksScopeControllerProvider.notifier).set(s),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(tasksListProvider),
            child: tasksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(
                error: e,
                onRetry: () => ref.invalidate(tasksListProvider),
              ),
              data: (tasks) {
                if (tasks.isEmpty) {
                  return _EmptyState(scope: scope);
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
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

class _ScopeChips extends StatelessWidget {
  final TasksScope scope;
  final void Function(TasksScope) onChange;

  const _ScopeChips({required this.scope, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        children: [
          for (final s in TasksScope.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(s.label),
                selected: s == scope,
                onSelected: (_) => onChange(s),
                selectedColor: AppColors.arenaBlue,
                showCheckmark: false,
                labelStyle: TextStyle(
                  color: s == scope ? Colors.white : AppColors.ink2,
                  fontSize: 13,
                  fontWeight:
                      s == scope ? FontWeight.w600 : FontWeight.w500,
                ),
                backgroundColor: AppColors.appBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: s == scope
                        ? AppColors.arenaBlue
                        : Colors.transparent,
                  ),
                ),
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
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
                  padding: const EdgeInsets.all(12),
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
                              borderRadius: BorderRadius.circular(8),
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
                                  backgroundColor: const Color(0xFFE5E7EB),
                                  valueColor: AlwaysStoppedAnimation(
                                      delivDone
                                          ? AppColors.greenBorder
                                          : AppColors.arenaBlue,),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
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
            'Done', Color(0xFFD1FAE5), AppColors.greenBorder,),
        TaskStatus.approved => const _StatusSpec(
            'Approved', Color(0xFFD1FAE5), AppColors.greenBorder,),
        'received' => const _StatusSpec(
            'Received', Color(0xFFEDE9FE), Color(0xFF6D28D9),),
        TaskStatus.awaitingClarification => const _StatusSpec(
            'Awaiting Clarification', Color(0xFFFEF3C7), Color(0xFFB45309),),
        TaskStatus.resumed => const _StatusSpec(
            'Resumed', AppColors.arenaBlueLight, AppColors.arenaBlue,),
        TaskStatus.archived =>
          const _StatusSpec('Archived', Color(0xFFEEF2F7), AppColors.ink3),
        TaskStatus.cancelled =>
          const _StatusSpec('Cancelled', Color(0xFFFEE2E2), AppColors.arenaRed),
        _ => _StatusSpec(s, const Color(0xFFEEF2F7), AppColors.ink2),
      };

  _PrioritySpec? _prioritySpec(String? p) => switch (p) {
        'urgent' => const _PrioritySpec('Urgent', AppColors.arenaRed),
        'high' => const _PrioritySpec('High', Color(0xFFEA580C)),
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
  final TasksScope scope;
  const _EmptyState({required this.scope});

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
                    'No tasks in "${scope.label}"',
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
