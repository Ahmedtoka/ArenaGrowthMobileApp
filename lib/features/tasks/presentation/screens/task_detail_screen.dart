import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
// `intl` exports its own `TextDirection` class that uses LTR/RTL static
// fields; hiding it here keeps the dart:ui (Flutter) enum (with .ltr/.rtl)
// as the unambiguous import for this file.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/api_exception.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/text_direction_util.dart';
import '../../../../core/widgets/attendance_guard.dart';
import '../../../../core/widgets/authed_network_image.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../chat/presentation/controllers/chat_providers.dart';
import '../../data/models/task_model.dart';
import '../controllers/tasks_providers.dart';

class TaskDetailScreen extends ConsumerWidget {
  final int taskId;
  const TaskDetailScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskAsync = ref.watch(taskDetailProvider(taskId));

    return Scaffold(
      backgroundColor: AppColors.appBg,
      appBar: AppBar(
        title: const Text('Task details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(taskDetailProvider(taskId)),
          ),
        ],
      ),
      body: taskAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 56, color: Colors.red),
                const SizedBox(height: 12),
                Text('Could not load task\n${e.toString()}',
                    textAlign: TextAlign.center,),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () =>
                      ref.invalidate(taskDetailProvider(taskId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (task) => _TaskDetailBody(task: task),
      ),
    );
  }
}

class _TaskDetailBody extends ConsumerStatefulWidget {
  final TaskModel task;
  const _TaskDetailBody({required this.task});

  @override
  ConsumerState<_TaskDetailBody> createState() => _TaskDetailBodyState();
}

class _TaskDetailBodyState extends ConsumerState<_TaskDetailBody> {
  bool _running = false;
  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();
    // Listen for chat events that relate to THIS task — task_done /
    // clarification_request / clarification_reply messages carry the
    // task_id in their payload. When one lands we invalidate the detail
    // provider so the screen refreshes immediately AND drop a snackbar so
    // the assignee sees the update even if the OS heads-up never appeared.
    final reverb = ref.read(reverbClientProvider);
    _realtimeSub = reverb.events.listen((event) {
      if (event.eventName == '__reconnected') {
        // Socket dropped + recovered while this task was open — any receive/
        // approve/clarification that happened meanwhile was never delivered
        // (Pusher doesn't replay). Refetch the task to catch up.
        ref.invalidate(taskDetailProvider(widget.task.id));
        return;
      }
      if (event.eventName != 'MessageSent') return;
      try {
        final payload = jsonDecode(event.rawData) as Map<String, dynamic>;
        final inner = payload['payload'] as Map<String, dynamic>?;
        if (inner == null) return;
        final mTaskId = inner['task_id'];
        final mTaskIds = inner['task_ids'];
        final matches = (mTaskId is num && mTaskId.toInt() == widget.task.id) ||
            (mTaskIds is List &&
                mTaskIds.any((e) => e is num && e.toInt() == widget.task.id));
        if (!matches) return;

        // Refresh the task so the timeline / status / revisions update.
        ref.invalidate(taskDetailProvider(widget.task.id));

        // Foreground hint when an OS notification might have been suppressed.
        final type = payload['type'] as String?;
        final hint = switch (type) {
          'clarification_reply' => '💬 Reply to your clarification arrived',
          'clarification_request' => '❓ Clarification requested on this task',
          'task_done' => inner['event'] == 'approved'
              ? '🎉 Task approved'
              : '✅ Task marked done',
          _ => null,
        };
        if (hint != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(hint),
              backgroundColor: AppColors.arenaBlue,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (_) {
        // Malformed payload — ignore, nothing we can do.
      }
    });
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  /// Work-gating: an employee may only act on a task (start, complete,
  /// request clarification, deliver) while they are checked-in AND active —
  /// not on break, not away, not checked-out. Returns true if allowed; else
  /// pops an explainer dialog and returns false.
  Future<bool> _ensureActive() => ref.ensureCheckedIn(context);

  Future<void> _action(
    String successMsg,
    Future<TaskModel> Function() call,
  ) async {
    setState(() => _running = true);
    try {
      final updated = await call();
      // Update the detail provider's cache with the new task.
      ref.invalidate(taskDetailProvider(widget.task.id));
      // Also refresh tasks list since status changed.
      ref.invalidate(tasksListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMsg)),
      );
      // Use the updated to suppress unused warning.
      assert(updated.id == widget.task.id);
    } catch (e) {
      if (!mounted) return;
      final msg = switch (e) {
        ApiException(:final message) => message,
        _ => e.toString(),
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $msg'),
          backgroundColor: AppColors.arenaRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final repo = ref.read(tasksRepositoryProvider);
    // Used to gate the "reply to clarification" button so only the task
    // creator can see/post it.
    final me = ref.watch(authControllerProvider).valueOrNull;
    final myId = me?.id;
    final amCreator = myId != null && t.creator?.id == myId;
    // View-only access (e.g. an account manager opening someone else's task)
    // must NOT see work actions — Start/Complete/Clarify are assignee-only.
    final amAssignee = myId != null && t.assignedToId == myId;
    // Who can hand a task off to the next stage: managers / AMs / owner, or
    // the person who created this task (typically the AM who owns the brief).
    final canHandoff = me != null &&
        (me.isOwner ||
            me.isAccountManager ||
            me.isDepartmentManager ||
            amCreator);

    // Separate plain description body from inline URLs so we can render the
    // URLs as link chips (matching the chat-card visual language).
    final (descBody, links) = _splitDescription(t.description);

    // Sprint J.2 — split attachments by lifecycle stage so the brief stays
    // separate from the assignee's completion / progress work.
    bool isImg(TaskAttachment a) => (a.mimeType ?? '').startsWith('image/');
    bool isKind(TaskAttachment a, String k) =>
        (a.kind) == k;

    final initialAttachments =
        t.attachments.where((a) => isKind(a, TaskAttachmentKind.initial)).toList();
    final completionAttachments = t.attachments
        .where((a) => isKind(a, TaskAttachmentKind.completion))
        .toList();
    final updateAttachments =
        t.attachments.where((a) => isKind(a, TaskAttachmentKind.update)).toList();

    final images = initialAttachments.where(isImg).toList();
    final files = initialAttachments.where((a) => !isImg(a)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        // 1. Pinned status pill — first thing the assignee sees.
        _StatusPill(task: t),
        const SizedBox(height: 10),

        // 2. Compact header: brand, title, due-date pill, created-by chip,
        //    priority. NO "Assigned to" (the viewer is the assignee).
        _HeaderV2(task: t),

        const SizedBox(height: 12),

        // 3. Action CTAs — visible and explicit so a fresh assignee knows
        //    what to do next.
        _ActionBar(
          task: t,
          running: _running,
          amCreator: amCreator,
          amAssignee: amAssignee,
          onStart: () async {
            if (!await _ensureActive()) return;
            await _action('Started working', () => repo.start(t.id));
          },
          onComplete: () async {
            if (!await _ensureActive()) return;
            await _askProofThenComplete(repo, t);
          },
          // Sprint R — Receive prompts an optional note ("sent to client X").
          onReceive: () async {
            if (!await _ensureActive()) return;
            await _askReceive(repo, t);
          },
          onApprove: () async {
            if (!await _ensureActive()) return;
            await _action('Task approved', () => repo.approve(t.id));
          },
          // Sprint R — Reject is now reachable from the task detail too,
          // not just from the chat card. Same reason prompt.
          onReject: () async {
            if (!await _ensureActive()) return;
            await _askRejectReason(repo, t);
          },
          onClarify: () async {
            if (!await _ensureActive()) return;
            await _askClarification(repo, t);
          },
          onReplyClarify: () async {
            if (!await _ensureActive()) return;
            await _askReplyClarification(repo, t);
          },
        ),

        // 3.2 Project chain timeline — shown when this task is part of a
        //     handoff pipeline (has a parent, a root, or onward children).
        if (t.isChained) ...[
          const SizedBox(height: 12),
          _ChainCard(taskId: t.id),
        ],

        // 3.3 Hand off to next stage — managers / AMs / owner / the creator.
        if (canHandoff) ...[
          const SizedBox(height: 12),
          _HandoffButton(task: t),
        ],

        // 3.5 Deliverables checklist (quantified task) — the assignee ticks
        //     off how many of each type they finished.
        if (t.deliverables.isNotEmpty) ...[
          const SizedBox(height: 12),
          _DeliverablesCard(
            taskId: t.id,
            deliverables: t.deliverables,
            // Ownership rule: only the assignee delivers — AND only while the
            // task is actively in progress (must press "Start working" first),
            // so time tracking + points stay correct.
            canEdit: amAssignee && t.isInProgress,
          ),
        ],

        // 4. Description with See more / copy.
        if (descBody.isNotEmpty) ...[
          const SizedBox(height: 12),
          _DescriptionCard(text: descBody),
        ],

        // 5. Link chips (Link 1, Link 2, …) with copy + open icons.
        if (links.isNotEmpty) ...[
          const SizedBox(height: 8),
          _LinksCard(urls: links),
        ],

        // 6. Image carousel (squares).
        if (images.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ImagesCard(images: images),
        ],

        // 7. Files (non-image attachments).
        if (files.isNotEmpty) ...[
          const SizedBox(height: 8),
          _FilesCard(files: files),
        ],

        // 8. Past clarifications (Q/A).
        if (t.revisions.isNotEmpty) ...[
          const SizedBox(height: 8),
          _RevisionsCard(task: t),
        ],

        // 9. Activity — completion deliverables + mid-work progress updates
        //    (Sprint J.2). Mirrors the desktop Section C.
        if (completionAttachments.isNotEmpty || updateAttachments.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ActivityCard(
            completion: completionAttachments,
            updates: updateAttachments,
          ),
        ],

        // 10. Collapsible timeline — last + closed by default so it doesn't
        //     crowd the page on entry.
        const SizedBox(height: 8),
        _TimelineCard(task: t),
      ],
    );
  }

  /// Strip inline URLs from the description so we can show them as separate
  /// link chips. Returns the trimmed text body + an ordered, deduped list of
  /// http(s) links found.
  (String, List<String>) _splitDescription(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return ('', const []);
    final matches = RegExp(r'https?://\S+').allMatches(text);
    final links =
        matches.map((m) => m.group(0)!).toSet().toList(growable: false);
    // Also drop the "🔗 Links:" header line that createBulkTask appends so we
    // don't end up with a dangling bullet.
    var body = text.replaceAll(RegExp(r'https?://\S+'), '');
    body = body.replaceAll(RegExp(r'🔗\s*Links?\s*:?', caseSensitive: false), '');
    body = body
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
    return (body, links);
  }

  /// Sprint J.4 — Complete with files + links. Opens a bottom sheet so the
  /// assignee can pick multiple images / files and add multiple URLs before
  /// marking the task done. Mirrors the desktop flow exactly.
  Future<void> _askProofThenComplete(
      dynamic repo, TaskModel t,) async {
    final result = await _CompleteTaskSheet.show(context, taskTitle: t.title);
    if (result == null || !mounted) return;
    if (result.files.isEmpty && result.links.isEmpty) {
      // Empty submit → keep the legacy quick-complete behaviour.
      await _action('Task completed', () => repo.complete(t.id));
      return;
    }
    await _action(
      'Task completed',
      () => repo.completeWithFiles(
        t.id,
        attachments: result.files,
        links: result.links,
      ),
    );
  }

  Future<void> _askClarification(dynamic repo, TaskModel t) async {
    final cycle = t.revisions.length + 1;
    final text = await _ClarificationSheet.show(
      context,
      kind: _ClarificationKind.request,
      cycle: cycle,
      taskTitle: t.title,
      counterpartLabel: 'To',
      counterpartName: t.creator?.name ?? 'Creator',
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    await _action(
      'Clarification $cycle sent',
      () => repo.requestClarification(t.id, text.trim()),
    );
  }

  /// Sprint R — prompts an optional note before flipping the task to
  /// Received. The note shows up in the chat card AND in the task
  /// timeline so the rest of the team has context.
  Future<void> _askReceive(dynamic repo, TaskModel t) async {
    final ctrl = TextEditingController();
    final picked = await showModalBottomSheet<({bool confirmed, String note})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom,),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(children: [
                Icon(Icons.inbox, color: Color(0xFF6366F1)),
                SizedBox(width: 8),
                Text('Mark as received',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700,),),
              ],),
              const SizedBox(height: 4),
              const Text(
                'Acknowledge that you got the deliverable. Add a quick note '
                "if you want (e.g. \"sent to client\") — it'll appear in the "
                'chat card. Approve/Reject becomes available right after.',
                style: TextStyle(fontSize: 12.5, color: AppColors.ink3),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Optional note…',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(
                    ctx, (confirmed: true, note: ctrl.text.trim()),),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: const Text('Mark as received',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700,),),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || !picked.confirmed || !mounted) return;
    await _action(
      'Marked as received',
      () => repo.receive(t.id, note: picked.note.isEmpty ? null : picked.note),
    );
  }

  /// Sprint R — Reject from task detail. Mirrors the in-chat reject sheet
  /// (Sprint J.3) and POSTs to /tasks/{id}/reject with a reason.
  Future<void> _askRejectReason(dynamic repo, TaskModel t) async {
    final ctrl = TextEditingController();
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom,),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(children: [
                Icon(Icons.close, color: AppColors.arenaRed),
                SizedBox(width: 8),
                Text('Reject task',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700,),),
              ],),
              const SizedBox(height: 4),
              const Text(
                'Tell the assignee what needs to change so they can fix '
                'and resubmit.',
                style: TextStyle(fontSize: 12.5, color: AppColors.ink3),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Reason for rejection…',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  final t = ctrl.text.trim();
                  if (t.length < 3) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('Please write a short reason.'),),);
                    return;
                  }
                  Navigator.pop(ctx, t);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.arenaRed,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: const Text('Send rejection',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700,),),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    await _action(
      'Task rejected — sent back to assignee',
      () => repo.reject(t.id, reason: reason),
    );
  }

  /// Creator answers a clarification request — posts the reply to the chat
  /// and resumes the task so the assignee can continue.
  Future<void> _askReplyClarification(dynamic repo, TaskModel t) async {
    // Latest open revision = the one we're answering.
    final cycle = t.revisions.length;
    final openRev = t.revisions.lastWhere(
      (r) => r.repliedAt == null,
      orElse: () => t.revisions.isNotEmpty
          ? t.revisions.last
          : const TaskRevision(id: 0),
    );
    final text = await _ClarificationSheet.show(
      context,
      kind: _ClarificationKind.reply,
      cycle: cycle,
      taskTitle: t.title,
      counterpartLabel: 'To',
      counterpartName: t.assignee?.name ?? 'Assignee',
      question: openRev.clarificationText,
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    await _action(
      'Clarification $cycle answered — task resumes',
      () => repo.replyClarification(t.id, text.trim()),
    );
  }
}

// ─── Clarification request / reply bottom sheet ────────────────────
enum _ClarificationKind { request, reply }

// ─── Complete-task sheet (Sprint J.4) ─────────────────────────────────────
// Returned by _CompleteTaskSheet.show — null if cancelled.
class CompleteTaskResult {
  final List<File> files;
  final List<String> links;
  const CompleteTaskResult({required this.files, required this.links});
}

class _CompleteTaskSheet extends StatefulWidget {
  final String taskTitle;
  const _CompleteTaskSheet({required this.taskTitle});

  static Future<CompleteTaskResult?> show(
    BuildContext context, {
    required String taskTitle,
  }) {
    return showModalBottomSheet<CompleteTaskResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CompleteTaskSheet(taskTitle: taskTitle),
    );
  }

  @override
  State<_CompleteTaskSheet> createState() => _CompleteTaskSheetState();
}

class _CompleteTaskSheetState extends State<_CompleteTaskSheet> {
  final List<File> _files = [];
  final List<String> _links = [];
  final TextEditingController _linkCtrl = TextEditingController();

  @override
  void dispose() {
    _linkCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;
    setState(() {
      for (final x in picked) {
        _files.add(File(x.path));
      }
    });
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    setState(() {
      for (final f in result.files) {
        if (f.path != null) _files.add(File(f.path!));
      }
    });
  }

  void _addLink() {
    final raw = _linkCtrl.text.trim();
    if (raw.isEmpty) return;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(raw)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Link must start with http:// or https://'),
      ),);
      return;
    }
    setState(() {
      _links.add(raw);
      _linkCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + viewInsets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grab handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Row(children: [
              Icon(Icons.check_circle, color: AppColors.greenBorder),
              SizedBox(width: 8),
              Text('Mark task as done',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700),),
            ],),
            const SizedBox(height: 6),
            Text(
              widget.taskTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.ink2),
            ),
            const SizedBox(height: 14),

            // ── Files (multi) ──
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('Add image'),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.attach_file, size: 18),
                  label: const Text('Add file'),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),),
                ),
              ),
            ],),
            if (_files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(_files.length, (i) {
                    final f = _files[i];
                    final name = f.path.split(Platform.pathSeparator).last;
                    final isImage = RegExp(
                            r'\.(jpe?g|png|webp|gif|heic)$',
                            caseSensitive: false,)
                        .hasMatch(name);
                    return Chip(
                      avatar: Icon(
                        isImage
                            ? Icons.image
                            : Icons.insert_drive_file_outlined,
                        size: 16,
                        color: AppColors.greenBorder,
                      ),
                      label: Text(
                        name.length > 22
                            ? '${name.substring(0, 22)}…'
                            : name,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      backgroundColor:
                          AppColors.greenBorder.withValues(alpha: 0.08),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () => setState(() => _files.removeAt(i)),
                    );
                  }),
                ),
              ),

            // ── Links ──
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _linkCtrl,
                  keyboardType: TextInputType.url,
                  onSubmitted: (_) => _addLink(),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Paste a link…',
                    hintText: 'https://…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _addLink,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.greenBorder,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
              ),
            ],),
            if (_links.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(_links.length, (i) {
                    final u = _links[i];
                    final short =
                        u.length > 32 ? '${u.substring(0, 32)}…' : u;
                    return Chip(
                      avatar: const Icon(Icons.link,
                          size: 16, color: AppColors.greenBorder,),
                      label: Text(short,
                          style: const TextStyle(fontSize: 11.5),),
                      backgroundColor:
                          AppColors.greenBorder.withValues(alpha: 0.08),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () => setState(() => _links.removeAt(i)),
                    );
                  }),
                ),
              ),

            // ── Action button ──
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                context,
                CompleteTaskResult(files: _files, links: _links),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.greenBorder,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.check, color: Colors.white),
              label: const Text(
                'Mark done & post',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClarificationSheet extends StatefulWidget {
  final _ClarificationKind kind;
  final int cycle;
  final String taskTitle;
  final String counterpartLabel;
  final String counterpartName;
  final String? question;

  const _ClarificationSheet({
    required this.kind,
    required this.cycle,
    required this.taskTitle,
    required this.counterpartLabel,
    required this.counterpartName,
    this.question,
  });

  static Future<String?> show(
    BuildContext context, {
    required _ClarificationKind kind,
    required int cycle,
    required String taskTitle,
    required String counterpartLabel,
    required String counterpartName,
    String? question,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ClarificationSheet(
        kind: kind,
        cycle: cycle,
        taskTitle: taskTitle,
        counterpartLabel: counterpartLabel,
        counterpartName: counterpartName,
        question: question,
      ),
    );
  }

  @override
  State<_ClarificationSheet> createState() => _ClarificationSheetState();
}

class _ClarificationSheetState extends State<_ClarificationSheet> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _title => widget.kind == _ClarificationKind.request
      ? '❓ Clarification request #${widget.cycle}'
      : '💬 Reply to clarification #${widget.cycle}';

  String get _ctaLabel => widget.kind == _ClarificationKind.request
      ? 'Send request'
      : 'Send reply';

  String get _hint => widget.kind == _ClarificationKind.request
      ? 'What do you need to clarify before continuing?'
      : 'Type your answer here';

  Color get _accent => widget.kind == _ClarificationKind.request
      ? const Color(0xFFB45309)
      : AppColors.arenaBlue;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + viewInsets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _accent,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.taskTitle,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
              decoration: BoxDecoration(
                color: AppColors.appBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 9,
                    backgroundColor: _accent,
                    child: Text(
                      widget.counterpartName.characters.first.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.counterpartLabel}: ${widget.counterpartName}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink2,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.question != null &&
                widget.question!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Question',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB45309),),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.question!.trim(),
                      style: const TextStyle(
                          fontSize: 13, height: 1.4, color: AppColors.ink,),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              minLines: 3,
              maxLines: 6,
              autofocus: true,
              decoration: InputDecoration(
                hintText: _hint,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: _sending
                  ? null
                  : () {
                      final text = _ctrl.text.trim();
                      if (text.isEmpty) return;
                      setState(() => _sending = true);
                      Navigator.of(context).pop(text);
                    },
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send, color: Colors.white),
              label: Text(
                _ctaLabel,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700,),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Status pill (pinned at top) ────────────────────────────────
class _StatusPill extends StatelessWidget {
  final TaskModel task;
  const _StatusPill({required this.task});

  ({Color bg, Color fg, IconData icon, String label}) _spec() {
    switch (task.status) {
      case TaskStatus.pending:
        return (
          bg: const Color(0xFFE0F2FE),
          fg: const Color(0xFF0369A1),
          icon: Icons.fiber_new,
          label: task.statusLabel ?? 'Pending'
        );
      case TaskStatus.inProgress:
        return (
          bg: AppColors.arenaBlueLight,
          fg: AppColors.arenaBlue,
          icon: Icons.play_arrow,
          label: task.statusLabel ?? 'In progress'
        );
      case TaskStatus.awaitingClarification:
        return (
          bg: const Color(0xFFFEF3C7),
          fg: const Color(0xFFB45309),
          icon: Icons.help_outline,
          label: task.statusLabel ?? 'Awaiting clarification'
        );
      case TaskStatus.resumed:
        return (
          bg: const Color(0xFFD1FAE5),
          fg: const Color(0xFF047857),
          icon: Icons.replay,
          label: task.statusLabel ?? 'Resumed — ready to work'
        );
      case TaskStatus.done:
        return (
          bg: const Color(0xFFD1FAE5),
          fg: const Color(0xFF065F46),
          icon: Icons.check,
          label: task.statusLabel ?? 'Awaiting approval'
        );
      case TaskStatus.approved:
        return (
          bg: const Color(0xFFD1FAE5),
          fg: const Color(0xFF047857),
          icon: Icons.verified,
          label: task.statusLabel ?? 'Approved'
        );
      case TaskStatus.cancelled:
        return (
          bg: AppColors.arenaRed.withValues(alpha: 0.10),
          fg: AppColors.arenaRed,
          icon: Icons.block,
          label: task.statusLabel ?? 'Cancelled'
        );
      default:
        return (
          bg: AppColors.appBg,
          fg: AppColors.ink2,
          icon: Icons.flag_outlined,
          label: task.statusLabel ?? task.status
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _spec();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: s.fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(s.icon, size: 16, color: s.fg),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              s.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: s.fg,
              ),
            ),
          ),
          if (task.priority != null && task.priority != 'medium')
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _priorityColor(task.priority!).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _priorityLabel(task.priority!),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _priorityColor(task.priority!),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _priorityLabel(String p) => switch (p) {
        'low' => 'Low priority',
        'medium' => 'Medium',
        'high' => 'High priority',
        'urgent' => 'Urgent',
        _ => p,
      };

  static Color _priorityColor(String p) => switch (p) {
        'urgent' => AppColors.arenaRed,
        'high' => const Color(0xFFEA580C),
        'low' => AppColors.ink3,
        _ => AppColors.arenaBlue,
      };
}

// ─── Compact header (brand chip · title · due pill · created by) ────────
class _HeaderV2 extends StatelessWidget {
  final TaskModel task;
  const _HeaderV2({required this.task});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.brand?.name != null)
            _BrandBadge(name: task.brand!.name, color: task.brand?.primaryColor),
          if (task.brand?.name != null) const SizedBox(height: 8),
          Text(
            task.title,
            textDirection: detectBidiDirection(task.title),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (task.timestamps?.dueAt != null)
                _DueChip(
                  dueAt: task.timestamps!.dueAt!,
                  isOverdue: task.isOverdue,
                ),
              if (task.creator != null)
                _PersonChip(
                  label: 'Created by',
                  name: task.creator!.name,
                  avatarUrl: task.creator!.avatarUrl,
                ),
              if (task.deliverables.isNotEmpty)
                _MiniChip(
                  icon: Icons.checklist,
                  label: '${task.deliverables.length} deliverables',
                  color: AppColors.ink2,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  final String name;
  final String? color;
  const _BrandBadge({required this.name, this.color});

  Color get _c {
    if (color == null || color!.isEmpty) return AppColors.arenaBlue;
    var hex = color!.replaceAll('#', '').trim();
    if (hex.length == 6) hex = 'FF$hex';
    final v = int.tryParse(hex, radix: 16);
    return v == null ? AppColors.arenaBlue : Color(v);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: _c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          name,
          style: TextStyle(
            fontSize: 12.5,
            color: _c,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DueChip extends StatelessWidget {
  final DateTime dueAt;
  final bool isOverdue;
  const _DueChip({required this.dueAt, required this.isOverdue});

  @override
  Widget build(BuildContext context) {
    final local = dueAt.toLocal();
    final today = DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day,);
    final dueDay = DateTime(local.year, local.month, local.day);
    final daysLeft = dueDay.difference(today).inDays;
    final Color bg, fg;
    final String label;
    if (isOverdue || daysLeft < 0) {
      bg = AppColors.arenaRed.withValues(alpha: 0.12);
      fg = AppColors.arenaRed;
      label = 'Overdue · ${DateFormat('MMM d, h:mm a').format(local)}';
    } else if (daysLeft == 0) {
      bg = AppColors.arenaRed.withValues(alpha: 0.12);
      fg = AppColors.arenaRed;
      label = 'Today · ${DateFormat('h:mm a').format(local)}';
    } else if (daysLeft == 1) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFB45309);
      label = 'Tomorrow · ${DateFormat('h:mm a').format(local)}';
    } else if (daysLeft <= 2) {
      bg = const Color(0xFFD1FAE5);
      fg = const Color(0xFF047857);
      label = '$daysLeft days · ${DateFormat('MMM d, h:mm a').format(local)}';
    } else {
      bg = const Color(0xFFE0F2FE);
      fg = const Color(0xFF0369A1);
      label = DateFormat('MMM d, y · h:mm a').format(local);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonChip extends StatelessWidget {
  final String label;
  final String name;
  final String? avatarUrl;
  const _PersonChip({
    required this.label,
    required this.name,
    this.avatarUrl,
  });

  Color _color() {
    final hues = [
      AppColors.arenaBlue,
      const Color(0xFFEC4899),
      const Color(0xFF10B981),
      const Color(0xFF8B5CF6),
      const Color(0xFFF59E0B),
    ];
    final hash = name.codeUnits.fold<int>(0, (a, c) => a + c);
    return hues[hash.abs() % hues.length];
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.fromLTRB(3, 3, 8, 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(
            name: name,
            avatarUrl: avatarUrl,
            size: 18,
            backgroundColor: color,
          ),
          const SizedBox(width: 5),
          Text(
            '$label  $name',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Description with See more + copy ───────────────────────────
class _DescriptionCard extends StatefulWidget {
  final String text;
  const _DescriptionCard({required this.text});

  @override
  State<_DescriptionCard> createState() => _DescriptionCardState();
}

class _DescriptionCardState extends State<_DescriptionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    const limit = 150;
    final long = widget.text.length > limit;
    final shown = (long && !_expanded)
        ? '${widget.text.substring(0, limit).trimRight()}…'
        : widget.text;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _SectionTitle('Description')),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                color: AppColors.ink3,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Copy description',
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: widget.text),);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Description copied')),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            shown,
            textDirection: detectBidiDirection(shown),
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: AppColors.ink,
            ),
          ),
          if (long)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    _expanded ? 'See less' : 'See more',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.arenaBlue,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Link 1 / Link 2 / Link 3 chips with copy + open ──────────────
class _LinksCard extends StatelessWidget {
  final List<String> urls;
  const _LinksCard({required this.urls});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Links'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < urls.length; i++)
                _LinkChip(label: 'Link ${i + 1}', url: urls[i]),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  final String label;
  final String url;
  const _LinkChip({required this.label, required this.url});

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label copied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.arenaBlueLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(20),),
            onTap: _open,
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(10, 6, 6, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link,
                      size: 14, color: AppColors.arenaBlue,),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.arenaBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(20),),
            onTap: () => _copy(context),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(4, 6, 10, 6),
              child: Icon(Icons.copy,
                  size: 14, color: AppColors.arenaBlue,),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Image carousel (horizontal squares) ────────────────────────
class _ImagesCard extends StatelessWidget {
  final List<TaskAttachment> images;
  const _ImagesCard({required this.images});

  void _openFullscreen(BuildContext context, int initialIndex) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ImageGallery(images: images, initialIndex: initialIndex),
    ),);
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Images (${images.length})'),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final att = images[i];
                return InkWell(
                  onTap: () => _openFullscreen(context, i),
                  borderRadius: BorderRadius.circular(10),
                  child: AuthedNetworkImage(
                    url: att.url,
                    width: 110,
                    height: 110,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(10),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageGallery extends StatefulWidget {
  final List<TaskAttachment> images;
  final int initialIndex;
  const _ImageGallery({required this.images, required this.initialIndex});

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  late final PageController _pc;
  late int _i;

  @override
  void initState() {
    super.initState();
    _i = widget.initialIndex;
    _pc = PageController(initialPage: _i);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_i + 1} / ${widget.images.length}'),
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.images.length,
        onPageChanged: (p) => setState(() => _i = p),
        itemBuilder: (_, idx) => InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Center(
            child: AuthedNetworkImage(
              url: widget.images[idx].url,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Files (non-image attachments) ───────────────────────────────
class _FilesCard extends ConsumerWidget {
  final List<TaskAttachment> files;
  const _FilesCard({required this.files});

  IconData _iconFor(String? mime) {
    if (mime == null) return Icons.insert_drive_file;
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('zip') || mime.contains('rar')) return Icons.archive;
    if (mime.contains('word') || mime.contains('document')) {
      return Icons.description;
    }
    if (mime.contains('sheet') || mime.contains('excel')) {
      return Icons.table_chart;
    }
    return Icons.insert_drive_file;
  }

  String _size(int? b) {
    if (b == null) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    TaskAttachment f,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(attachmentDownloaderProvider).downloadAndOpen(
            f.url,
            filename: f.originalName,
            mimeType: f.mimeType,
          );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open file: $e')),
      );
    }
  }

  Future<void> _share(
    BuildContext context,
    WidgetRef ref,
    TaskAttachment f,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(attachmentDownloaderProvider).downloadAndShare(
            f.url,
            filename: f.originalName,
          );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Files (${files.length})'),
          const SizedBox(height: 6),
          for (final f in files)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 2),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.arenaBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    Icon(_iconFor(f.mimeType), size: 18, color: Colors.white),
              ),
              title: Text(
                f.originalName ?? 'File',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,),
              ),
              subtitle: Text(
                _size(f.sizeBytes),
                style:
                    const TextStyle(fontSize: 11.5, color: AppColors.ink3),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share, size: 18),
                    color: AppColors.ink3,
                    onPressed: () => _share(context, ref, f),
                    tooltip: 'Share',
                  ),
                  IconButton(
                    icon: const Icon(Icons.download, size: 18),
                    color: AppColors.ink3,
                    onPressed: () => _download(context, ref, f),
                    tooltip: 'Download',
                  ),
                ],
              ),
              onTap: () => _download(context, ref, f),
            ),
        ],
      ),
    );
  }
}

// ─── Activity card (Sprint J.2) ─────────────────────────────────
// Renders BOTH completion deliverables (KIND_COMPLETION) and mid-work
// progress updates (KIND_UPDATE) in a single section. Mirrors the desktop
// "Activity" card so a user sees the same separation on either client.
class _ActivityCard extends ConsumerWidget {
  final List<TaskAttachment> completion;
  final List<TaskAttachment> updates;

  const _ActivityCard({
    required this.completion,
    required this.updates,
  });

  /// Sprint Q.2 — download with bearer token then open with OS handler
  /// (image viewer, PDF reader, etc).
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    TaskAttachment a,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(attachmentDownloaderProvider).downloadAndOpen(
            a.url,
            filename: a.originalName,
            mimeType: a.mimeType,
          );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open: $e')),
      );
    }
  }

  Future<void> _share(
    BuildContext context,
    WidgetRef ref,
    TaskAttachment a,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(attachmentDownloaderProvider).downloadAndShare(
            a.url,
            filename: a.originalName,
          );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  Widget _subhead(String label, Color dotColor, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '($count)',
          style: const TextStyle(fontSize: 11.5, color: AppColors.ink3),
        ),
      ],),
    );
  }

  Widget _imageGrid(
    BuildContext context,
    WidgetRef ref,
    List<TaskAttachment> imgs,
  ) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: imgs.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemBuilder: (ctx, i) {
        final a = imgs[i];
        // AuthedNetworkImage carries its own placeholder + errorWidget so
        // we don't need to pass an errorBuilder here — broken images get a
        // built-in icon fallback automatically.
        return GestureDetector(
          onTap: () => _open(context, ref, a),
          onLongPress: () => _share(context, ref, a),
          child: AuthedNetworkImage(
            url: a.url,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(8),
          ),
        );
      },
    );
  }

  Widget _fileList(
    BuildContext context,
    WidgetRef ref,
    List<TaskAttachment> files,
    Color accent,
  ) {
    return Column(
      children: [
        for (final f in files)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 2),
            leading: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.insert_drive_file_outlined,
                  size: 16, color: Colors.white,),
            ),
            title: Text(
              f.originalName ?? 'File',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              (f.sizeBytes ?? 0) == 0
                  ? ''
                  : '${((f.sizeBytes ?? 0) / 1024).toStringAsFixed(1)} KB',
              style: const TextStyle(fontSize: 11, color: AppColors.ink3),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.share, size: 18, color: accent),
                  onPressed: () => _share(context, ref, f),
                  tooltip: 'Share',
                ),
                IconButton(
                  icon: Icon(Icons.download, size: 18, color: accent),
                  onPressed: () => _open(context, ref, f),
                  tooltip: 'Download',
                ),
              ],
            ),
            onTap: () => _open(context, ref, f),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completionImages = completion
        .where((a) => (a.mimeType ?? '').startsWith('image/'))
        .toList();
    final completionFiles = completion
        .where((a) => !(a.mimeType ?? '').startsWith('image/'))
        .toList();
    final updateImages =
        updates.where((a) => (a.mimeType ?? '').startsWith('image/')).toList();
    final updateFiles =
        updates.where((a) => !(a.mimeType ?? '').startsWith('image/')).toList();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Activity'),
          const SizedBox(height: 10),

          // ── Completion deliverables ──
          if (completion.isNotEmpty) ...[
            _subhead('Completion deliverables',
                AppColors.greenBorder, completion.length,),
            if (completionImages.isNotEmpty) ...[
              _imageGrid(context, ref, completionImages),
              const SizedBox(height: 6),
            ],
            if (completionFiles.isNotEmpty)
              _fileList(
                  context, ref, completionFiles, AppColors.greenBorder,),
          ],

          // ── Mid-work updates ──
          if (updates.isNotEmpty) ...[
            if (completion.isNotEmpty) const SizedBox(height: 12),
            _subhead('Progress updates', AppColors.arenaBlue, updates.length),
            if (updateImages.isNotEmpty) ...[
              _imageGrid(context, ref, updateImages),
              const SizedBox(height: 6),
            ],
            if (updateFiles.isNotEmpty)
              _fileList(context, ref, updateFiles, AppColors.arenaBlue),
          ],
        ],
      ),
    );
  }
}

// ─── Collapsible timeline ───────────────────────────────────────
class _TimelineCard extends StatefulWidget {
  final TaskModel task;
  const _TimelineCard({required this.task});

  @override
  State<_TimelineCard> createState() => _TimelineCardState();
}

class _TimelineCardState extends State<_TimelineCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ts = widget.task.timestamps;
    if (ts == null) return const SizedBox.shrink();

    // Build the events in chronological order:
    //   Created → Opened → Start working → (Clarification N requested →
    //   Clarification N answered → Start working N+1)... → Completed → Approved
    final entries = <(String, DateTime, IconData, Color)>[];
    if (ts.createdAt != null) {
      entries.add(
          ('Created', ts.createdAt!, Icons.fiber_new, AppColors.ink3),);
    }
    if (ts.firstOpenedAt != null) {
      entries.add(('Opened', ts.firstOpenedAt!, Icons.visibility,
          AppColors.arenaBlue),);
    }
    if (ts.startedWorkingAt != null) {
      entries.add(('Start working', ts.startedWorkingAt!, Icons.play_arrow,
          AppColors.arenaBlue),);
    }

    // Walk the revisions (TaskRevision is sorted by id on the backend so the
    // first row in the list is cycle 1). For each cycle we emit up to three
    // events with the cycle number baked into the label so the user can read
    // them as "Start working 2", "Clarification 3 requested", etc.
    final revs = widget.task.revisions;
    for (var i = 0; i < revs.length; i++) {
      final r = revs[i];
      final cycle = i + 1;
      if (r.requestedAt != null) {
        entries.add((
          'Clarification $cycle requested',
          r.requestedAt!,
          Icons.help_outline,
          const Color(0xFFB45309),
        ),);
      }
      if (r.repliedAt != null) {
        entries.add((
          'Clarification $cycle answered',
          r.repliedAt!,
          Icons.reply_all,
          AppColors.arenaBlue,
        ),);
      }
      if (r.resumedAt != null) {
        // The 1st start is "Start working"; each subsequent resume is
        // numbered from 2 upward (cycle 1 reply → Start working 2).
        entries.add((
          'Start working ${cycle + 1}',
          r.resumedAt!,
          Icons.replay,
          AppColors.greenBorder,
        ),);
      }
    }

    if (ts.completedAt != null) {
      entries.add(('Completed', ts.completedAt!, Icons.check_circle,
          AppColors.greenBorder),);
    }
    // Sprint R — Received milestone between Completed and Approved.
    if (ts.receivedAt != null) {
      entries.add(('Received', ts.receivedAt!, Icons.inbox,
          const Color(0xFF6366F1)),);
    }
    if (ts.approvedAt != null) {
      entries.add((
        'Approved',
        ts.approvedAt!,
        Icons.verified,
        AppColors.greenBorder
      ),);
    }
    if (ts.cancelledAt != null) {
      entries.add(
          ('Cancelled', ts.cancelledAt!, Icons.block, AppColors.arenaRed),);
    }

    if (entries.isEmpty) return const SizedBox.shrink();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: _SectionTitle('Timeline'),
                  ),
                  Text(
                    '${entries.length} events',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.ink3,),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.expand_more,
                        size: 20, color: AppColors.ink3,),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [
                  for (final e in entries)
                    _TimelineRow(
                        label: e.$1, time: e.$2, icon: e.$3, color: e.$4,),
                ],
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final String label;
  final DateTime time;
  final IconData icon;
  final Color color;
  const _TimelineRow({
    required this.label,
    required this.time,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.ink,
                  fontWeight: FontWeight.w500,),
            ),
          ),
          Text(
            DateFormat('d/M · h:mm a').format(time.toLocal()),
            style: const TextStyle(fontSize: 11.5, color: AppColors.ink3),
          ),
        ],
      ),
    );
  }
}

class _RevisionsCard extends StatelessWidget {
  final TaskModel task;
  const _RevisionsCard({required this.task});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _SectionTitle('Clarifications')),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2,),
                decoration: BoxDecoration(
                  color: AppColors.arenaBlueLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${task.revisions.length} cycle${task.revisions.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.arenaBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < task.revisions.length; i++) ...[
            _RevisionBlock(
              revision: task.revisions[i],
              cycleNumber: i + 1,
            ),
            if (i < task.revisions.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _RevisionBlock extends StatelessWidget {
  final TaskRevision revision;
  final int cycleNumber;

  const _RevisionBlock({required this.revision, required this.cycleNumber});

  @override
  Widget build(BuildContext context) {
    final hasReply = revision.replyText != null &&
        revision.replyText!.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ink3.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cycle header strip
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 6,),
            decoration: const BoxDecoration(
              color: Color(0xFFFEF3C7),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.help_outline,
                    size: 13, color: Color(0xFFB45309),),
                const SizedBox(width: 5),
                Text(
                  'Cycle $cycleNumber',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB45309),
                  ),
                ),
                const Spacer(),
                if (revision.responseLabel != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule,
                          size: 11, color: Color(0xFFB45309),),
                      const SizedBox(width: 3),
                      Text(
                        revision.responseLabel!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // Q
          if (revision.clarificationText != null)
            _QaRow(
              kind: 'Q',
              accent: const Color(0xFFB45309),
              text: revision.clarificationText!,
              at: revision.requestedAt,
            ),
          if (hasReply)
            Container(
              height: 1,
              color: AppColors.ink3.withValues(alpha: 0.12),
            ),
          // A
          if (hasReply)
            _QaRow(
              kind: 'A',
              accent: AppColors.arenaBlue,
              text: revision.replyText!,
              at: revision.repliedAt,
            )
          else
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Row(
                children: [
                  Icon(Icons.hourglass_top,
                      size: 13, color: AppColors.warning,),
                  SizedBox(width: 5),
                  Text(
                    'Awaiting answer…',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _QaRow extends StatelessWidget {
  final String kind;
  final Color accent;
  final String text;
  final DateTime? at;
  const _QaRow({
    required this.kind,
    required this.accent,
    required this.text,
    required this.at,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              kind,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text.trim(),
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.ink,
                  ),
                ),
                if (at != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      DateFormat('d/M · h:mm a').format(at!.toLocal()),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.ink3,),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final TaskModel task;
  final bool running;
  final bool amCreator;
  final bool amAssignee;
  final VoidCallback onStart;
  final VoidCallback onComplete;
  final VoidCallback onReceive; // Sprint R
  final VoidCallback onApprove;
  final VoidCallback onReject; // Sprint R — surface alongside Approve
  final VoidCallback onClarify;
  final VoidCallback onReplyClarify;

  const _ActionBar({
    required this.task,
    required this.running,
    required this.amCreator,
    required this.amAssignee,
    required this.onStart,
    required this.onComplete,
    required this.onReceive,
    required this.onApprove,
    required this.onReject,
    required this.onClarify,
    required this.onReplyClarify,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];

    // "Open task" button is intentionally omitted — opening the task
    // (i.e. landing on this screen) already records first_opened_at on the
    // server, so a manual Open action would be redundant.
    // Work actions are ASSIGNEE-only. Anyone else (account manager, dept
    // manager…) opens the task read-only — no Start/Clarify/Complete.
    if (task.canStart && amAssignee) {
      final isResume = task.status == TaskStatus.resumed;
      buttons.add(_ActionButton(
        // Distinct label after a clarification cycle so the assignee sees
        // they're re-engaging, not starting from scratch.
        label: isResume ? 'Start working again' : 'Start working',
        icon: isResume ? Icons.replay : Icons.play_arrow,
        primary: true,
        // Use the green resume tone in the resume case so the visual cue
        // matches the "Resumed" timeline entry.
        color: isResume ? AppColors.greenBorder : null,
        onPressed: running ? null : onStart,
      ),);
    }
    if (task.canRequestClarification && amAssignee) {
      buttons.add(_ActionButton(
        label: 'Request clarification',
        icon: Icons.help_outline,
        onPressed: running ? null : onClarify,
      ),);
    }
    // Only the creator can reply to a clarification request — the assignee
    // already saw their own request and doesn't need the button.
    if (task.canReplyClarification && amCreator) {
      buttons.add(_ActionButton(
        label: 'Answer clarification',
        icon: Icons.reply,
        primary: true,
        color: AppColors.arenaBlue,
        onPressed: running ? null : onReplyClarify,
      ),);
    }
    if (task.canComplete && amAssignee) {
      buttons.add(_ActionButton(
        label: 'Complete task',
        icon: Icons.check_circle_outline,
        primary: true,
        color: AppColors.greenBorder,
        onPressed: running ? null : onComplete,
      ),);
    }
    // Sprint R — Receive is the mandatory gateway from DONE. Only the
    // creator sees it; the assignee just waits until the creator marks
    // the deliverable received.
    if (task.canReceive && amCreator) {
      buttons.add(_ActionButton(
        label: 'Mark as received',
        icon: Icons.inbox,
        primary: true,
        color: const Color(0xFF6366F1),
        onPressed: running ? null : onReceive,
      ),);
    }
    // Sprint R — Approve+Reject only show AFTER receive (status=received).
    if (task.canApprove && amCreator) {
      buttons.add(_ActionButton(
        label: 'Approve',
        icon: Icons.verified,
        primary: true,
        color: AppColors.greenBorder,
        onPressed: running ? null : onApprove,
      ),);
    }
    if (task.canReject && amCreator) {
      buttons.add(_ActionButton(
        label: 'Reject',
        icon: Icons.close,
        primary: true,
        color: AppColors.arenaRed,
        onPressed: running ? null : onReject,
      ),);
    }

    if (buttons.isEmpty) {
      return _Card(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              task.isApproved ? '✅ Task complete & approved' : 'No actions available',
              style: const TextStyle(color: AppColors.ink3),
            ),
          ),
        ),
      );
    }

    return Column(
      children: buttons
          .map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: b,
              ),)
          .toList(),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final Color? color;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.arenaBlue;
    if (primary) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: c,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: c),
        label: Text(label, style: TextStyle(color: c)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: c),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

// ─── Small reusable bits ────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        // Transparent Material ancestor so ListTiles inside a card render
        // their ink/background correctly (Flutter 3.44 asserts otherwise).
        child: Material(
          type: MaterialType.transparency,
          child: child,
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.ink2,
        ),
      );
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MiniChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  }) : valueColor = null;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.ink3),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.ink3,),),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      color: valueColor ?? AppColors.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Quantified-deliverables checklist. The assignee bumps the `done` count per
/// type and saves; the backend syncs the design ledger. Trust model.
class _DeliverablesCard extends ConsumerStatefulWidget {
  final int taskId;
  final List<dynamic> deliverables;
  final bool canEdit;
  const _DeliverablesCard({
    required this.taskId,
    required this.deliverables,
    required this.canEdit,
  });

  @override
  ConsumerState<_DeliverablesCard> createState() => _DeliverablesCardState();
}

class _DeliverablesCardState extends ConsumerState<_DeliverablesCard> {
  int _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? 0}') ?? 0;

  List<Map<String, dynamic>> get _items => widget.deliverables
      .map<Map<String, dynamic>>((e) => (e as Map).cast<String, dynamic>())
      .toList();

  String _label(Map<String, dynamic> d) {
    final l = d['label'] as String?;
    if (l != null && l.isNotEmpty) return l;
    final t = d['type']?.toString() ?? '';
    return t
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Future<void> _openDeliver(Map<String, dynamic> d) async {
    // Work-gating: delivering only while checked-in AND active.
    if (!await ref.ensureCheckedIn(context)) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DeliverSheet(
        taskId: widget.taskId,
        type: d['type'].toString(),
        label: _label(d),
        done: _int(d['done']),
        qty: _int(d['qty']),
      ),
    );
    if (ok == true && mounted) {
      ref.invalidate(taskDetailProvider(widget.taskId));
      ref.invalidate(tasksListProvider);
    }
  }

  Future<void> _openItem(Map<String, dynamic> it) async {
    final url = it['url'] as String?;
    if (url == null || url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final totReq = items.fold<int>(0, (a, b) => a + _int(b['qty']));
    final totDone = items.fold<int>(0, (a, b) => a + _int(b['done']));
    final pct = totReq > 0 ? (totDone / totReq * 100).round() : 0;
    final allDone = totReq > 0 && totDone >= totReq;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('🎯 Deliverables & delivery',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),),
              Text('$totDone/$totReq · $pct%',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: allDone ? AppColors.greenBorder : AppColors.ink2,),),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: totReq > 0 ? totDone / totReq : 0,
              minHeight: 6,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: AlwaysStoppedAnimation(
                  allDone ? AppColors.greenBorder : AppColors.arenaBlue,),
            ),
          ),
          const SizedBox(height: 10),
          for (final d in items) ...[
            _row(d),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> d) {
    final done = _int(d['done']);
    final qty = _int(d['qty']);
    final complete = qty > 0 && done >= qty;
    final delivItems = (d['items'] is List) ? (d['items'] as List) : const [];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  complete
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: complete
                      ? AppColors.greenBorder
                      : Colors.grey.shade400,),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_label(d),
                    textDirection: detectBidiDirection(_label(d)),
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600,),),
              ),
              Text('$done/$qty',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color:
                          complete ? AppColors.greenBorder : AppColors.ink2,),),
            ],
          ),
          if (qty > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (done / qty).clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: const Color(0xFFE5E7EB),
                valueColor: AlwaysStoppedAnimation(
                    complete ? AppColors.greenBorder : AppColors.arenaBlue,),
              ),
            ),
          ],
          if (delivItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final raw in delivItems)
                  Builder(builder: (_) {
                    final it = (raw as Map).cast<String, dynamic>();
                    final isLink = it['kind'] == 'link';
                    final units = _int(it['units']);
                    final name = (it['name'] as String?) ??
                        (isLink ? 'Link' : 'File');
                    return InkWell(
                      onTap: () => _openItem(it),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4,),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                              isLink
                                  ? Icons.link
                                  : Icons.insert_drive_file_outlined,
                              size: 13,
                              color: AppColors.arenaBlue,),
                          const SizedBox(width: 4),
                          Text(
                              isLink
                                  ? (units > 1 ? 'Link ×$units' : 'Link')
                                  : (name.length > 16
                                      ? '${name.substring(0, 16)}…'
                                      : name),
                              style: const TextStyle(
                                  fontSize: 11.5, color: AppColors.ink2,),),
                        ],),
                      ),
                    );
                  },),
              ],
            ),
          ],
          if (widget.canEdit && !complete) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openDeliver(d),
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text('Deliver · ${qty - done} left'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.arenaBlue,
                  side: const BorderSide(color: AppColors.arenaBlue),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Per-deliverable delivery sheet: pick files (each = 1 unit) and/or paste a
/// link covering N units, then submit. Shows a live upload progress bar.
class _DeliverSheet extends ConsumerStatefulWidget {
  final int taskId;
  final String type;
  final String label;
  final int done;
  final int qty;
  const _DeliverSheet({
    required this.taskId,
    required this.type,
    required this.label,
    required this.done,
    required this.qty,
  });

  @override
  ConsumerState<_DeliverSheet> createState() => _DeliverSheetState();
}

class _DeliverSheetState extends ConsumerState<_DeliverSheet> {
  final List<File> _files = [];
  final TextEditingController _linkCtrl = TextEditingController();
  late final TextEditingController _unitsCtrl;
  bool _saving = false;
  double _pct = 0;

  int get _remaining => (widget.qty - widget.done).clamp(0, widget.qty);

  @override
  void initState() {
    super.initState();
    _unitsCtrl =
        TextEditingController(text: (_remaining > 0 ? _remaining : 1).toString());
  }

  @override
  void dispose() {
    _linkCtrl.dispose();
    _unitsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;
    setState(() {
      for (final x in picked) {
        _files.add(File(x.path));
      }
    });
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    setState(() {
      for (final f in result.files) {
        if (f.path != null) _files.add(File(f.path!));
      }
    });
  }

  Future<void> _submit() async {
    final link = _linkCtrl.text.trim();
    final hasLink = link.isNotEmpty;
    if (_files.isEmpty && !hasLink) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add files or a link first')),
      );
      return;
    }
    if (hasLink && !RegExp(r'^https?://', caseSensitive: false).hasMatch(link)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link must start with http:// or https://')),
      );
      return;
    }
    setState(() {
      _saving = true;
      _pct = 0;
    });
    try {
      await ref.read(tasksRepositoryProvider).deliverDeliverable(
            widget.taskId,
            type: widget.type,
            files: _files,
            link: hasLink ? link : null,
            linkUnits: int.tryParse(_unitsCtrl.text.trim()) ?? 1,
            onProgress: (p) {
              if (mounted) setState(() => _pct = p);
            },
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delivery failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final willAdd = _files.length +
        (_linkCtrl.text.trim().isNotEmpty
            ? (int.tryParse(_unitsCtrl.text.trim()) ?? 1)
            : 0);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + viewInsets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),),
              ),
            ),
            const SizedBox(height: 14),
            Text('Deliver: ${widget.label}',
                textDirection: detectBidiDirection(widget.label),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),),
            const SizedBox(height: 2),
            Text('Required ${widget.qty} · Delivered ${widget.done} · Left $_remaining',
                style: const TextStyle(fontSize: 12.5, color: AppColors.ink3),),
            const SizedBox(height: 14),

            // Files — each counts as 1.
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _pickImages,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('Photos'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _pickFiles,
                  icon: const Icon(Icons.attach_file, size: 18),
                  label: const Text('Files'),
                ),
              ),
            ],),
            if (_files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(_files.length, (i) {
                    final name =
                        _files[i].path.split(Platform.pathSeparator).last;
                    return Chip(
                      label: Text(
                          name.length > 20 ? '${name.substring(0, 20)}…' : name,
                          style: const TextStyle(fontSize: 11.5),),
                      onDeleted:
                          _saving ? null : () => setState(() => _files.removeAt(i)),
                    );
                  }),
                ),
              ),

            const SizedBox(height: 12),
            const Text('Or a link (Drive / Behance / …)',
                style: TextStyle(fontSize: 12.5, color: AppColors.ink3),),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _linkCtrl,
                    keyboardType: TextInputType.url,
                    enabled: !_saving,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'https://…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _unitsCtrl,
                    keyboardType: TextInputType.number,
                    enabled: !_saving && _linkCtrl.text.trim().isNotEmpty,
                    textAlign: TextAlign.center,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Units',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),

            if (willAdd > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Delivering $willAdd unit(s) now',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.arenaBlue,),),
              ),

            if (_saving) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _pct == 0 ? null : _pct,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.arenaBlue),
                ),
              ),
              const SizedBox(height: 4),
              Text('Uploading… ${(_pct * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.ink3),),
            ],

            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.arenaBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _saving ? null : _submit,
              icon: const Icon(Icons.check, color: Colors.white),
              label: Text(_saving ? 'Delivering…' : 'Deliver',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600,),),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon}) : onTap = null;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            size: 18,
            color: onTap == null ? const Color(0xFFCBD5E1) : AppColors.ink2,),
      ),
    );
  }
}

// ════════════════ Task chain (handoff pipeline) ════════════════

const _chainStatusColors = <String, Color>{
  'pending': Color(0xFF6B7280),
  'in_progress': AppColors.arenaBlue,
  'awaiting_clarification': Color(0xFFB45309),
  'resumed': AppColors.arenaBlue,
  'done': Color(0xFF0891B2),
  'received': Color(0xFF7C3AED),
  'approved': Color(0xFF047857),
  'cancelled': Color(0xFF9CA3AF),
  'archived': Color(0xFF9CA3AF),
};

/// Timeline of the whole project chain — the root brief + every handed-off
/// stage. Tapping a stage opens that task.
class _ChainCard extends ConsumerWidget {
  final int taskId;
  const _ChainCard({required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chainAsync = ref.watch(taskChainProvider(taskId));
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('🔗 Project chain'),
          const SizedBox(height: 8),
          chainAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),),
              ),
            ),
            error: (e, _) => const Text('Could not load the chain',
                style: TextStyle(color: AppColors.ink3, fontSize: 12),),
            data: (stages) {
              if (stages.length < 2) {
                return const Text('Single stage only',
                    style: TextStyle(color: AppColors.ink3, fontSize: 12),);
              }
              return Column(
                children: [
                  for (var i = 0; i < stages.length; i++)
                    _ChainRow(
                      stage: stages[i],
                      index: i + 1,
                      isLast: i == stages.length - 1,
                      isCurrent: stages[i].id == taskId,
                      color: _chainStatusColors[stages[i].status] ??
                          const Color(0xFF6B7280),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ChainRow extends StatelessWidget {
  final TaskModel stage;
  final int index;
  final bool isLast;
  final bool isCurrent;
  final Color color;
  const _ChainRow({
    required this.stage,
    required this.index,
    required this.isLast,
    required this.isCurrent,
    required this.color,
  });

  int _sum(String key) => stage.deliverables.fold<int>(
        0,
        (s, d) => s + (((d as Map)[key] ?? 0) as num).toInt(),
      );

  @override
  Widget build(BuildContext context) {
    final req = _sum('qty');
    final done = _sum('done');
    return InkWell(
      onTap: isCurrent
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TaskDetailScreen(taskId: stage.id),),),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Text('$index',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,),),
                ),
                if (!isLast)
                  Container(width: 1, height: 26, color: const Color(0xFFE5E7EB)),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: isCurrent
                    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                    : EdgeInsets.zero,
                decoration: isCurrent
                    ? BoxDecoration(
                        color: AppColors.arenaBlueLight,
                        borderRadius: BorderRadius.circular(8),)
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            stage.title + (isCurrent ? ' · here' : ''),
                            textDirection: detectBidiDirection(stage.title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: isCurrent
                                    ? AppColors.arenaBlue
                                    : AppColors.ink,),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2,),
                          decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),),
                          child: Text(stage.statusLabel ?? stage.status,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: color,),),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '👤 ${stage.assignee?.name ?? 'Unassigned'}'
                      '${stage.department != null ? ' · ${stage.department}' : ''}'
                      '${req > 0 ? ' · 🎯 $done/$req' : ''}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.ink3),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Entry card → opens the handoff sheet. Visible to managers / AMs / owner /
/// the task creator.
class _HandoffButton extends ConsumerWidget {
  final TaskModel task;
  const _HandoffButton({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Vertical layout on purpose: the previous Row → Expanded(Column) collapsed
    // to ~1-char width in this position (text rendered letter-per-line). Direct
    // Column children always get the card's real width, so text wraps normally.
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: const [
              Icon(Icons.alt_route, size: 18, color: AppColors.arenaBlue),
              SizedBox(width: 6),
              Expanded(
                child: Text('Hand off to next stage',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          const Text('Create the next task with the same deliverables',
              style: TextStyle(fontSize: 11.5, color: AppColors.ink3)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                // Work-gate: must be checked-in + active to hand off.
                if (!await ref.ensureCheckedIn(context)) return;
                final ok = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) => _HandoffSheet(task: task),
                );
                if (ok == true) {
                  ref.invalidate(taskDetailProvider(task.id));
                  ref.invalidate(taskChainProvider(task.id));
                }
              },
              child: const Text('Hand off'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HandoffSheet extends ConsumerStatefulWidget {
  final TaskModel task;
  const _HandoffSheet({required this.task});

  @override
  ConsumerState<_HandoffSheet> createState() => _HandoffSheetState();
}

class _HandoffSheetState extends ConsumerState<_HandoffSheet> {
  final _titleCtrl = TextEditingController();
  final _briefCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _delivTypeCtrl = TextEditingController();
  int _delivQty = 1;
  final List<Map<String, dynamic>> _deliverables = [];
  String _priority = 'medium';
  bool _carry = true;
  int? _assigneeId;
  String? _assigneeName;
  List<Map<String, dynamic>> _users = [];
  bool _loadingUsers = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl.text = 'Follow-up: ${widget.task.title}';
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await ref.read(tasksRepositoryProvider).listUsers();
      if (mounted) setState(() { _users = users; _loadingUsers = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _briefCtrl.dispose();
    _searchCtrl.dispose();
    _delivTypeCtrl.dispose();
    super.dispose();
  }

  void _addDeliv() {
    final type = _delivTypeCtrl.text.trim();
    if (type.isEmpty) return;
    setState(() {
      _deliverables.add({'type': type, 'qty': _delivQty});
      _delivTypeCtrl.clear();
      _delivQty = 1;
    });
  }

  Future<void> _submit() async {
    if (_assigneeId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick a person first')));
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final picked = _users.firstWhere((u) => u['id'] == _assigneeId,
          orElse: () => const {},);
      await ref.read(tasksRepositoryProvider).handoff(
            widget.task.id,
            assigneeId: _assigneeId!,
            title: _titleCtrl.text.trim(),
            brief: _briefCtrl.text.trim().isEmpty ? null : _briefCtrl.text.trim(),
            department: picked['department'] as String?,
            priority: _priority,
            carryOutputs: _carry,
            deliverables: _deliverables,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Handoff failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _users
        : _users
            .where((u) =>
                (u['name'] ?? '').toString().toLowerCase().contains(q),)
            .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + viewInsets),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),),
              ),
            ),
            const SizedBox(height: 12),
            const Text('↪️ Hand off to next stage',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),),
            const SizedBox(height: 12),

            // Assignee
            const Text('Hand off to',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink3,),),
            const SizedBox(height: 4),
            if (_assigneeName != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  label: Text(_assigneeName!),
                  onDeleted: () => setState(() {
                    _assigneeId = null;
                    _assigneeName = null;
                  }),
                ),
              ),
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search a person…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 150,
              child: _loadingUsers
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final u = filtered[i];
                        final selected = u['id'] == _assigneeId;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          title: Text((u['name'] ?? '').toString(),
                              textDirection: detectBidiDirection(
                                  (u['name'] ?? '').toString(),),),
                          subtitle: u['department'] != null
                              ? Text(u['department'].toString())
                              : null,
                          trailing: selected
                              ? const Icon(Icons.check,
                                  color: AppColors.arenaBlue,)
                              : null,
                          onTap: () => setState(() {
                            _assigneeId = u['id'] as int;
                            _assigneeName = u['name'] as String?;
                          }),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                  labelText: 'Task title', border: OutlineInputBorder(),),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _briefCtrl,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(
                  labelText: 'Short brief (optional)',
                  border: OutlineInputBorder(),),
            ),
            const SizedBox(height: 12),

            // Deliverables for this stage
            const Text('🎯 Deliverables for this stage (optional)',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink3,),),
            const SizedBox(height: 6),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _delivTypeCtrl,
                    decoration: const InputDecoration(
                        hintText: 'Post, Reel…',
                        border: OutlineInputBorder(),
                        isDense: true,),
                  ),
                ),
                IconButton(
                  onPressed: _delivQty > 1
                      ? () => setState(() => _delivQty--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_delivQty',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16,),),
                IconButton(
                  onPressed: () => setState(() => _delivQty++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
                ElevatedButton(
                    onPressed: _addDeliv, child: const Text('Add'),),
              ],
            ),
            if (_deliverables.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < _deliverables.length; i++)
                      Chip(
                        label: Text(
                            '${_deliverables[i]['qty']}× ${_deliverables[i]['type']}',),
                        onDeleted: () =>
                            setState(() => _deliverables.removeAt(i)),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // Priority
            const Text('Priority',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink3,),),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final p in const ['low', 'medium', 'high', 'urgent'])
                  ChoiceChip(
                    label: Text(p),
                    selected: _priority == p,
                    onSelected: (_) => setState(() => _priority = p),
                  ),
              ],
            ),

            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _carry,
              onChanged: (v) => setState(() => _carry = v ?? true),
              title: const Text('Attach this stage’s deliverables as reference',
                  style: TextStyle(fontSize: 13),),
            ),
            const SizedBox(height: 4),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: Text(_saving ? '...' : '↪️ Create next stage'),
            ),
          ],
        ),
      ),
    );
  }
}
