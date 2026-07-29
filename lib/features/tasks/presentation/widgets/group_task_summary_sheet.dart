import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/text_direction_util.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/models/task_model.dart';
import '../../data/repositories/tasks_repository.dart';
import '../controllers/tasks_providers.dart';

/// Live "who's working on what" board for a brand group — total open tasks +
/// a per-assignee breakdown. Tap a person to see their open tasks here.
class GroupTaskSummarySheet extends ConsumerStatefulWidget {
  final int groupId;
  final String groupTitle;
  const GroupTaskSummarySheet({
    super.key,
    required this.groupId,
    required this.groupTitle,
  });

  static Future<void> show(
    BuildContext context, {
    required int groupId,
    required String groupTitle,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => GroupTaskSummarySheet(
        groupId: groupId,
        groupTitle: groupTitle,
      ),
    );
  }

  @override
  ConsumerState<GroupTaskSummarySheet> createState() =>
      _GroupTaskSummarySheetState();
}

class _GroupTaskSummarySheetState extends ConsumerState<GroupTaskSummarySheet> {
  bool _loading = true;
  String? _error;
  int _totalOpen = 0;
  int? _brandId;
  List<Map<String, dynamic>> _byAssignee = const [];

  // Drill-down state
  Map<String, dynamic>? _drillPerson;
  bool _drillLoading = false;
  List<TaskModel> _drillTasks = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(tasksRepositoryProvider);
      final data = await repo.groupTaskSummary(widget.groupId);
      if (!mounted) return;
      setState(() {
        _totalOpen = (data['total_open'] as num?)?.toInt() ?? 0;
        _brandId = (data['brand_id'] as num?)?.toInt();
        _byAssignee = ((data['by_assignee'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Couldn’t load the summary.';
        _loading = false;
      });
    }
  }

  Future<void> _openPerson(Map<String, dynamic> person) async {
    setState(() {
      _drillPerson = person;
      _drillLoading = true;
      _drillTasks = const [];
    });
    try {
      final repo = ref.read(tasksRepositoryProvider);
      final result = await repo.list(
        filter: TasksFilter(
          brandId: _brandId,
          assignee: (person['assignee_id'] as num?)?.toInt(),
          status: 'active',
        ),
      );
      if (!mounted) return;
      setState(() {
        _drillTasks = result.tasks;
        _drillLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _drillLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            const Divider(height: 1),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!,
                              style: const TextStyle(color: AppColors.ink3),),
                        )
                      : _drillPerson != null
                          ? _drillView()
                          : _summaryView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final inDrill = _drillPerson != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 16, 10),
      child: Row(
        children: [
          if (inDrill)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _drillPerson = null),
            )
          else
            const Padding(
              padding: EdgeInsets.only(left: 4, right: 8),
              child: Icon(Icons.dashboard_outlined, color: AppColors.arenaBlue),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inDrill
                      ? (_drillPerson!['assignee_name'] as String? ?? '')
                      : 'Open tasks',
                  textDirection: detectBidiDirection(inDrill
                      ? (_drillPerson!['assignee_name'] as String? ?? '')
                      : null,),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700,),
                ),
                Text(
                  inDrill ? widget.groupTitle : '$_totalOpen open in total',
                  style: const TextStyle(fontSize: 12, color: AppColors.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryView() {
    if (_byAssignee.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text('No open tasks 🎉',
              style: TextStyle(color: AppColors.ink3),),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _byAssignee.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = _byAssignee[i];
        final name = p['assignee_name'] as String? ?? 'Unassigned';
        final count = (p['count'] as num?)?.toInt() ?? 0;
        return ListTile(
          leading: UserAvatar(
            name: name,
            avatarUrl: p['avatar_url'] as String?,
            size: 38,
          ),
          title: Text(name,
              textDirection: detectBidiDirection(name),
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,),),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.arenaBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$count',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.arenaBlue,),),
          ),
          onTap: () => _openPerson(p),
        );
      },
    );
  }

  Widget _drillView() {
    if (_drillLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_drillTasks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
            child: Text('No open tasks',
                style: TextStyle(color: AppColors.ink3),),),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _drillTasks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final t = _drillTasks[i];
        return ListTile(
          title: Text(t.title,
              textDirection: detectBidiDirection(t.title),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5),),
          subtitle: Text(t.statusLabel ?? t.status,
              style: const TextStyle(fontSize: 11.5, color: AppColors.ink3),),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () {
            Navigator.pop(context);
            context.push('/tasks/${t.id}');
          },
        );
      },
    );
  }
}
