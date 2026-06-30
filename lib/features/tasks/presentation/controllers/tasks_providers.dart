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

/// Active filter for the tasks list — controlled by the segmented chips
/// at the top of the screen.
enum TasksScope { all, mine, awaiting, inProgress, done }

extension TasksScopeX on TasksScope {
  String get label => switch (this) {
        TasksScope.all => 'All',
        TasksScope.mine => 'Mine',
        TasksScope.awaiting => 'Awaiting',
        TasksScope.inProgress => 'In Progress',
        TasksScope.done => 'Done',
      };

  TasksFilter toFilter() => switch (this) {
        TasksScope.all => const TasksFilter(),
        TasksScope.mine => const TasksFilter(mine: true),
        TasksScope.awaiting =>
          const TasksFilter(status: TaskStatus.awaitingClarification),
        TasksScope.inProgress =>
          const TasksFilter(status: TaskStatus.inProgress),
        TasksScope.done => const TasksFilter(status: TaskStatus.done),
      };
}

@riverpod
class TasksScopeController extends _$TasksScopeController {
  @override
  TasksScope build() => TasksScope.mine;

  void set(TasksScope scope) => state = scope;
}

@riverpod
Future<List<TaskModel>> tasksList(
  TasksListRef ref,
) async {
  final scope = ref.watch(tasksScopeControllerProvider);
  final repo = ref.read(tasksRepositoryProvider);
  return repo.list(filter: scope.toFilter());
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
