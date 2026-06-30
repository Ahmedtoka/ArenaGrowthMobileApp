import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/utils/upload_prep.dart';
import '../models/task_model.dart';

/// Filter set for the tasks index endpoint.
class TasksFilter {
  final String? status;
  final int? brandId;
  final String? department;
  final int? assignee;
  final bool mine;

  const TasksFilter({
    this.status,
    this.brandId,
    this.department,
    this.assignee,
    this.mine = false,
  });
}

class TasksRepository {
  final DioClient _client;
  TasksRepository(this._client);

  /// GET /api/team/tasks?status=...&brand_id=...&department=...&mine=1
  Future<List<TaskModel>> list({TasksFilter filter = const TasksFilter()}) async {
    final res = await _client.get(
      ApiConstants.tasks,
      query: {
        if (filter.status != null) 'status': filter.status,
        if (filter.brandId != null) 'brand_id': filter.brandId,
        if (filter.department != null) 'department': filter.department,
        if (filter.assignee != null) 'assignee': filter.assignee,
        if (filter.mine) 'mine': 1,
      },
    );
    final data = res.data as Map<String, dynamic>;
    final list = (data['tasks'] ?? data['data'] ?? []) as List<dynamic>;
    return list
        .map((t) => TaskModel.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/team/groups/{id}/task-summary — live per-assignee open counts.
  Future<Map<String, dynamic>> groupTaskSummary(int groupId) async {
    final res = await _client.get(ApiConstants.groupTaskSummary(groupId));
    return res.data as Map<String, dynamic>;
  }

  /// GET /api/team/tasks/{id} — full detail with relations.
  Future<TaskModel> get(int id) async {
    final res = await _client.get(ApiConstants.task(id));
    final data = res.data as Map<String, dynamic>;
    final task = data['task'] as Map<String, dynamic>;
    return TaskModel.fromJson(task);
  }

  // ─── Lifecycle actions ──────────────────────────────────────
  Future<TaskModel> open(int id) async =>
      _runAction((c) => c.post(ApiConstants.taskOpen(id)));

  Future<TaskModel> start(int id) async =>
      _runAction((c) => c.post(ApiConstants.taskStart(id)));

  Future<TaskModel> requestClarification(int id, String text) async =>
      _runAction((c) => c.post(
            ApiConstants.taskClarify(id),
            data: {'text': text},
          ),);

  /// Creator posts the clarification answer → backend resumes the task.
  Future<TaskModel> replyClarification(int id, String text) async =>
      _runAction((c) => c.post(
            ApiConstants.taskClarifyReply(id),
            data: {'text': text},
          ),);

  /// Legacy single-link complete. Kept so the old call sites keep working.
  Future<TaskModel> complete(int id, {String? proofLink}) async =>
      _runAction((c) => c.post(
            ApiConstants.taskComplete(id),
            data: {if (proofLink != null) 'proof_link': proofLink},
          ),);

  /// Sprint J.4 — Complete with multiple files + multiple links. Goes through
  /// `/complete-with-file` (multipart). The backend writes each file as a
  /// TaskAttachment kind=completion + builds the rich task_done chat card
  /// with image previews + download chips.
  Future<TaskModel> completeWithFiles(
    int id, {
    List<File> attachments = const [],
    List<String> links = const [],
  }) async {
    final form = FormData.fromMap({
      for (var i = 0; i < links.length; i++) 'links[$i]': links[i],
    });
    // Compress big images in PARALLEL before building the multipart body —
    // ten 20MB photos become ~1-2MB each, so the upload takes seconds.
    final prepared = await Future.wait(attachments.map(UploadPrep.prepare));
    for (final f in prepared) {
      form.files.add(MapEntry(
        'attachments[]',
        await MultipartFile.fromFile(
          f.path,
          filename: f.path.split(Platform.pathSeparator).last,
        ),
      ),);
    }
    return _runAction((c) => c.post(
          ApiConstants.taskCompleteWithFile(id),
          data: form,
        ),);
  }

  Future<TaskModel> approve(int id) async =>
      _runAction((c) => c.post(ApiConstants.taskApprove(id)));

  /// PATCH /team/tasks/{id}/deliverables — update done counts (trust model).
  Future<TaskModel> updateDeliverables(
    int id,
    List<Map<String, dynamic>> deliverables,
  ) async =>
      _runAction((c) => c.patch(
            ApiConstants.taskDeliverables(id),
            data: {'deliverables': deliverables},
          ),);

  /// POST /team/tasks/{id}/deliverables/deliver — deliver against ONE
  /// deliverable type: files (each = 1 unit) and/or a link (covers `linkUnits`
  /// units). Supports partial delivery; the server recomputes done.
  Future<TaskModel> deliverDeliverable(
    int id, {
    required String type,
    List<File> files = const [],
    String? link,
    int linkUnits = 1,
    void Function(double pct)? onProgress,
  }) async {
    final form = FormData.fromMap({
      'type': type,
      if (link != null && link.isNotEmpty) 'link': link,
      if (link != null && link.isNotEmpty) 'link_units': linkUnits.toString(),
    });
    final prepared = await Future.wait(files.map(UploadPrep.prepare));
    for (final f in prepared) {
      form.files.add(MapEntry(
        'files[]',
        await MultipartFile.fromFile(
          f.path,
          filename: f.path.split(Platform.pathSeparator).last,
        ),
      ),);
    }
    return _runAction((c) => c.post(
          ApiConstants.taskDeliver(id),
          data: form,
          onSendProgress: onProgress == null
              ? null
              : (sent, total) {
                  if (total > 0) onProgress((sent / total).clamp(0.0, 1.0));
                },
        ),);
  }

  /// POST /team/tasks/{id}/handoff — create the NEXT stage task, seeded with
  /// this task's finished outputs. Returns the newly created task.
  Future<TaskModel> handoff(
    int id, {
    required int assigneeId,
    required String title,
    String? brief,
    String? department,
    int? brandId,
    String priority = 'medium',
    DateTime? dueAt,
    bool carryOutputs = true,
    List<Map<String, dynamic>> deliverables = const [],
  }) async =>
      _runAction((c) => c.post(
            ApiConstants.taskHandoff(id),
            data: {
              'assigned_to_id': assigneeId,
              'title': title,
              if (brief != null && brief.isNotEmpty) 'description': brief,
              if (department != null && department.isNotEmpty)
                'department': department,
              if (brandId != null) 'brand_id': brandId,
              'priority': priority,
              if (dueAt != null) 'due_at': dueAt.toIso8601String(),
              'carry_outputs': carryOutputs,
              if (deliverables.isNotEmpty) 'deliverables': deliverables,
            },
          ),);

  /// GET /team/tasks/{id}/chain — the whole project chain (root brief + every
  /// handed-off stage), ordered, for the timeline.
  Future<List<TaskModel>> chain(int id) async {
    final res = await _client.get(ApiConstants.taskChain(id));
    final data = res.data as Map<String, dynamic>;
    final stages = (data['stages'] ?? []) as List<dynamic>;
    return stages
        .map((t) => TaskModel.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  /// GET /team/users — all active users (assignee picker for handoff). Optional
  /// fuzzy search.
  Future<List<Map<String, dynamic>>> listUsers({String? search}) async {
    final res = await _client.get(
      ApiConstants.users,
      query: {
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'limit': 100,
      },
    );
    final data = res.data as Map<String, dynamic>;
    final users = data['users'] as List<dynamic>;
    return users.cast<Map<String, dynamic>>();
  }

  /// Sprint J.3 — Creator rejects the done task with a reason. The backend
  /// bumps rejection_count, bounces the task to STATUS_RESUMED, and posts a
  /// task_done chat card tagged event=rejected so the assignee sees + gets
  /// pushed.
  Future<TaskModel> reject(int id, {required String reason}) async =>
      _runAction((c) => c.post(
            '/team/tasks/$id/reject',
            data: {'reason': reason},
          ),);

  /// Sprint R — Creator (or owner / brand admin) marks the deliverable as
  /// received. Required step between complete and approve/reject. The
  /// task flips DONE → RECEIVED; a system card with event=received gets
  /// dropped into the chat. `note` is optional context like "sent to
  /// client for review".
  Future<TaskModel> receive(int id, {String? note}) async => _runAction(
        (c) => c.post(
          '/team/tasks/$id/receive',
          data: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
        ),
      );

  /// Personal to-do — creates a task assigned to me (one per brand). The
  /// brand list is required because `tasks.brand_id` is NOT NULL.
  Future<void> createSelfTask({
    required String title,
    String? description,
    required List<int> brandIds,
    DateTime? dueAt,
    String priority = 'medium',
  }) async {
    await _client.post(
      ApiConstants.mySelfTasks,
      data: {
        'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        'brand_ids': brandIds,
        if (dueAt != null) 'due_at': dueAt.toIso8601String(),
        'priority': priority,
      },
    );
  }

  /// GET /api/team/me/brands — brands the user can see, used by the self-
  /// task picker. Returns a slim payload of {id, name, primary_color}.
  Future<List<Map<String, dynamic>>> listMyBrands({bool all = false}) async {
    final res = await _client.get(
      ApiConstants.myBrands,
      query: all ? {'all': 1} : null,
    );
    final data = res.data as Map<String, dynamic>;
    final brands = data['brands'] as List<dynamic>;
    return brands.cast<Map<String, dynamic>>();
  }

  /// GET /api/team/tasks/form-config?assignee_id=X
  /// Role-aware deliverable types for the Add-Task form — changes with the
  /// selected employee's department. Returns the raw payload:
  /// {department, role, role_label, deliverable_types:[{key,label}, …]}.
  Future<Map<String, dynamic>> taskFormConfig({int? assigneeId, String? department}) async {
    final res = await _client.get(
      ApiConstants.taskFormConfig,
      query: {
        if (assigneeId != null) 'assignee_id': assigneeId,
        if (department != null && department.trim().isNotEmpty) 'department': department.trim(),
      },
    );
    return (res.data as Map).cast<String, dynamic>();
  }

  /// GET /api/team/tasks/available-slots?assignee_id=X&date=YYYY-MM-DD
  /// Returns the hourly sockets for that assignee on that day:
  /// {slots:[{hour, available, reason}], …}. Booked / past hours come back
  /// with available=false so the picker can disable them.
  Future<List<Map<String, dynamic>>> taskAvailableSlots({
    required int assigneeId,
    required String date,
  }) async {
    final res = await _client.get(
      ApiConstants.taskAvailableSlots,
      query: {'assignee_id': assigneeId, 'date': date},
    );
    final data = (res.data as Map).cast<String, dynamic>();
    final slots = (data['slots'] as List<dynamic>? ?? const []);
    return slots.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  /// GET /api/team/users?group_id={groupId}&search={search}
  /// Returns members of a brand-chat group, optionally filtered by search.
  /// Used by the chat-task assignee picker.
  Future<List<Map<String, dynamic>>> listGroupUsers(
    int groupId, {
    String? search,
  }) async {
    final res = await _client.get(
      ApiConstants.users,
      query: {
        'group_id': groupId,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'limit': 100,
      },
    );
    final data = res.data as Map<String, dynamic>;
    final users = data['users'] as List<dynamic>;
    return users.cast<Map<String, dynamic>>();
  }

  /// Create ONE task per assignee from a chat message. Returns the list of
  /// created task IDs. Loops because the backend accepts a single
  /// assigned_to_id per call — we get the right back-end behaviour
  /// (audit log + chat card per task) for free this way.
  Future<List<int>> createTasksFromMessage({
    int? brandId, // null → private task (DM with the assignee)
    required int sourceMessageId,
    required List<int> assigneeIds,
    required String title,
    String? description,
    required String department,
    DateTime? dueAt,
    String priority = 'medium',
    // Sprint I.2 — files + URL links picked in the in-chat task creator.
    // When non-empty we switch to multipart so the backend persists the
    // attachments alongside the task and surfaces them on the chat card.
    List<File> attachments = const [],
    List<String> links = const [],
    // Quantified deliverables: [{type, qty, done}]
    List<Map<String, dynamic>> deliverables = const [],
    // 0.0–1.0 upload progress across ALL assignees (drives the sheet's bar).
    void Function(double pct)? onProgress,
  }) async {
    final created = <int>[];
    final hasUploads = attachments.isNotEmpty;
    // Compress big images ONCE (in parallel) before any per-assignee loop —
    // the single biggest speed win for "task with many photos".
    final prepared = hasUploads
        ? await Future.wait(attachments.map(UploadPrep.prepare))
        : const <File>[];
    final total = assigneeIds.length;
    for (var idx = 0; idx < assigneeIds.length; idx++) {
      final assigneeId = assigneeIds[idx];
      late final Response res;
      if (hasUploads) {
        // multipart so files travel as `attachments[]` (Laravel arrays).
        final formMap = <String, dynamic>{
          if (brandId != null) 'brand_id': brandId.toString(),
          'assigned_to_id': assigneeId.toString(),
          'title': title,
          if (description != null && description.isNotEmpty)
            'description': description,
          'department': department,
          'priority': priority,
          if (dueAt != null) 'due_at': dueAt.toIso8601String(),
          'source_message_id': sourceMessageId.toString(),
          for (var i = 0; i < links.length; i++) 'links[$i]': links[i],
        };
        // Send deliverables as NESTED form fields (deliverables[i][key]) so
        // Laravel parses them as a real array — the server validates
        // `deliverables => array`, and a JSON string would fail with
        // "deliverables must be an array" (422).
        for (var i = 0; i < deliverables.length; i++) {
          final d = deliverables[i];
          formMap['deliverables[$i][type]'] = (d['type'] ?? '').toString();
          formMap['deliverables[$i][qty]'] = (d['qty'] ?? 1).toString();
          formMap['deliverables[$i][done]'] = (d['done'] ?? 0).toString();
        }
        final form = FormData.fromMap(formMap);
        for (final f in prepared) {
          form.files.add(MapEntry(
            'attachments[]',
            await MultipartFile.fromFile(
              f.path,
              filename: f.path.split(Platform.pathSeparator).last,
            ),
          ),);
        }
        res = await _client.post(
          ApiConstants.tasks,
          data: form,
          onSendProgress: onProgress == null
              ? null
              : (sent, count) {
                  if (count <= 0) return;
                  // Spread progress across the per-assignee fan-out so the bar
                  // fills smoothly from 0→100% over all uploads, not per task.
                  final frac = (idx + sent / count) / total;
                  onProgress(frac.clamp(0.0, 1.0));
                },
        );
      } else {
        res = await _client.post(
          ApiConstants.tasks,
          data: {
            if (brandId != null) 'brand_id': brandId,
            'assigned_to_id': assigneeId,
            'title': title,
            if (description != null && description.isNotEmpty)
              'description': description,
            'department': department,
            'priority': priority,
            if (dueAt != null) 'due_at': dueAt.toIso8601String(),
            'source_message_id': sourceMessageId,
            if (links.isNotEmpty) 'links': links,
            if (deliverables.isNotEmpty) 'deliverables': deliverables,
          },
        );
      }
      final data = res.data as Map<String, dynamic>;
      final task = data['task'] as Map<String, dynamic>;
      created.add(task['id'] as int);
    }
    return created;
  }

  Future<TaskModel> _runAction(
    Future<dynamic> Function(DioClient c) call,
  ) async {
    final res = await call(_client);
    final data = res.data as Map<String, dynamic>;
    final task = data['task'] as Map<String, dynamic>;
    return TaskModel.fromJson(task);
  }
}
