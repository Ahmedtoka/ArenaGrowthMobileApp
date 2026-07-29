import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/providers/app_providers.dart';

/// One row in the action-center (a mention, a clarification, a done task, or a
/// task update). Kept as a plain class (no codegen) so it's easy to evolve.
class ActionItem {
  final int id;
  final int? groupId;
  final int? messageId;
  final String title; // actor name (mentions) OR task title
  final String subtitle; // snippet / who / status line
  final DateTime? at;

  const ActionItem({
    required this.id,
    this.groupId,
    this.messageId,
    required this.title,
    required this.subtitle,
    this.at,
  });

  factory ActionItem.mention(Map<String, dynamic> j) => ActionItem(
        id: j['id'] as int,
        groupId: j['group_id'] as int?,
        messageId: j['message_id'] as int?,
        title: (j['actor'] ?? '—').toString(),
        subtitle: (j['snippet'] ?? 'mentioned you').toString(),
        at: _date(j['at']),
      );

  factory ActionItem.task(Map<String, dynamic> j, {required String sub}) => ActionItem(
        id: j['id'] as int,
        title: (j['title'] ?? 'Task').toString(),
        subtitle: sub,
        at: _date(j['at']),
      );

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}

class ActionCenterBundle {
  final int unread;
  final List<ActionItem> mentions;
  final List<ActionItem> clarifications;
  final List<ActionItem> tasksDone;
  final List<ActionItem> updates;

  const ActionCenterBundle({
    required this.unread,
    required this.mentions,
    required this.clarifications,
    required this.tasksDone,
    required this.updates,
  });
}

final actionCenterProvider =
    FutureProvider.autoDispose<ActionCenterBundle>((ref) async {
  final client = ref.read(dioClientProvider);
  final res = await client.get(ApiConstants.actionCenter);
  final d = res.data as Map<String, dynamic>;
  List<Map<String, dynamic>> list(String k) =>
      ((d[k] as List<dynamic>?) ?? const [])
          .map((e) => e as Map<String, dynamic>)
          .toList();

  return ActionCenterBundle(
    unread: (d['unread'] ?? 0) as int,
    mentions: list('mentions').map(ActionItem.mention).toList(),
    clarifications: list('clarifications')
        .map((j) => ActionItem.task(j, sub: 'from ${j['by'] ?? '—'}'))
        .toList(),
    tasksDone: list('tasks_done')
        .map((j) => ActionItem.task(j, sub: '${j['by'] ?? '—'} finished it'))
        .toList(),
    updates: list('updates')
        .map((j) => ActionItem.task(j, sub: '${j['status'] ?? 'updated'} · ${j['by'] ?? ''}'))
        .toList(),
  );
});

/// Mark the seen-based categories (tasks done · updates) as viewed.
Future<void> markActionCenterSeen(WidgetRef ref) async {
  try {
    await ref.read(dioClientProvider).post(ApiConstants.actionCenterSeen);
  } catch (_) {/* best-effort */}
}
