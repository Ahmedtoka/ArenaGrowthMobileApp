import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/providers/app_providers.dart';
import '../../data/models/task_model.dart';
import '../../data/repositories/tasks_repository.dart';

part 'tasks_providers.g.dart';

@Riverpod(keepAlive: true)
TasksRepository tasksRepository(TasksRepositoryRef ref) {
  final client = ref.watch(dioClientProvider);
  return TasksRepository(client);
}

// ─────────────────────────────────────────────────────────────────────
// Status tabs — the lifecycle stages every employee sees for their tasks.
// ─────────────────────────────────────────────────────────────────────
// Order matters — this is the on-screen tab order: New first, All last.
enum TaskTab { newTasks, inProgress, waiting, delivered, done, all }

extension TaskTabX on TaskTab {
  String get label => switch (this) {
        TaskTab.newTasks => 'New',
        TaskTab.inProgress => 'In Progress',
        TaskTab.waiting => 'Waiting',
        TaskTab.delivered => 'Delivered',
        TaskTab.done => 'Done',
        TaskTab.all => 'All',
      };

  /// Server status key. `null` = All (no status filter).
  String? get statusKey => switch (this) {
        TaskTab.newTasks => 'new',
        TaskTab.inProgress => 'in_progress',
        TaskTab.waiting => 'awaiting',
        TaskTab.delivered => 'delivered',
        TaskTab.done => 'completed',
        TaskTab.all => null,
      };
}

// ─────────────────────────────────────────────────────────────────────
// Date range — same day/week/month/custom vocabulary as the rest of the app.
// ─────────────────────────────────────────────────────────────────────
// On-screen order: Today · This Month · All time · Custom.
enum TaskDateRange { today, month, all, custom }

extension TaskDateRangeX on TaskDateRange {
  String get label => switch (this) {
        TaskDateRange.today => 'Today',
        TaskDateRange.month => 'This Month',
        TaskDateRange.all => 'All time',
        TaskDateRange.custom => 'Custom',
      };

  /// Server range key. `null` = all time (no date bound).
  String? get apiKey => switch (this) {
        TaskDateRange.today => 'today',
        TaskDateRange.month => 'month',
        TaskDateRange.all => null,
        TaskDateRange.custom => 'custom',
      };
}

/// Custom [from, to] window, only used when the range is `custom`.
class TaskCustomWindow {
  final DateTime? from;
  final DateTime? to;
  const TaskCustomWindow({this.from, this.to});
}

// ─── State controllers ────────────────────────────────────────────────

@riverpod
class TaskTabController extends _$TaskTabController {
  @override
  TaskTab build() => TaskTab.newTasks; // default opens on "New"
  void set(TaskTab tab) => state = tab;
}

@riverpod
class TaskRangeController extends _$TaskRangeController {
  @override
  TaskDateRange build() => TaskDateRange.today; // default opens on "Today"
  void set(TaskDateRange range) => state = range;
}

@riverpod
class TaskCustomRangeController extends _$TaskCustomRangeController {
  @override
  TaskCustomWindow build() => const TaskCustomWindow();
  void set({DateTime? from, DateTime? to}) =>
      state = TaskCustomWindow(from: from, to: to);
}

/// Manager-only assignee filter (null = everyone).
@riverpod
class TaskFilterAssignee extends _$TaskFilterAssignee {
  @override
  int? build() => null;
  void set(int? id) => state = id;
}

/// Manager-only brand filter (null = all brands).
@riverpod
class TaskFilterBrand extends _$TaskFilterBrand {
  @override
  int? build() => null;
  void set(int? id) => state = id;
}

// ─── The list itself (tasks + live open counts) ───────────────────────

@riverpod
Future<TasksResult> tasksList(TasksListRef ref) async {
  final tab = ref.watch(taskTabControllerProvider);
  final range = ref.watch(taskRangeControllerProvider);
  final custom = ref.watch(taskCustomRangeControllerProvider);
  final assignee = ref.watch(taskFilterAssigneeProvider);
  final brand = ref.watch(taskFilterBrandProvider);
  final repo = ref.read(tasksRepositoryProvider);
  return repo.list(
    filter: TasksFilter(
      status: tab.statusKey,
      range: range.apiKey,
      dateFrom: range == TaskDateRange.custom ? custom.from : null,
      dateTo: range == TaskDateRange.custom ? custom.to : null,
      assignee: assignee,
      brandId: brand,
    ),
  );
}

/// Employee list for the manager filter dropdown.
@riverpod
Future<List<Map<String, dynamic>>> taskFilterEmployees(
  TaskFilterEmployeesRef ref,
) async {
  final repo = ref.read(tasksRepositoryProvider);
  return repo.listUsers();
}

/// Brand list for the manager filter dropdown — MY brands only, so a manager
/// can only ever filter within the brands they oversee.
@riverpod
Future<List<Map<String, dynamic>>> taskFilterBrands(
  TaskFilterBrandsRef ref,
) async {
  final repo = ref.read(tasksRepositoryProvider);
  return repo.listMyBrands(all: false);
}

@riverpod
Future<TaskModel> taskDetail(TaskDetailRef ref, int taskId) async {
  final repo = ref.read(tasksRepositoryProvider);
  return repo.get(taskId);
}

/// The whole project chain (root brief + every handed-off stage) for the
/// timeline shown on a chained task's detail screen.
@riverpod
Future<List<TaskModel>> taskChain(TaskChainRef ref, int taskId) async {
  final repo = ref.read(tasksRepositoryProvider);
  return repo.chain(taskId);
}
