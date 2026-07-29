import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/utils/text_direction_util.dart';
import '../../../../core/widgets/authed_network_image.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/models/message_model.dart';

/// Unified card for system messages — task_card / meeting_card / task_done /
/// clarification_request. Driven by the message payload (rich structured
/// data) rather than parsing the body string.
///
/// Visual spec (Arena task card v2):
///   ┌────────────────────────────────────────────────────────┐
///   │  📋 New task                              11:38 PM     │ ← header
///   ├────────────────────────────────────────────────────────┤
///   │  TITLE OF THE TASK (bold, ~16px)                       │
///   │                                                        │
///   │  Assigned to  ▢ Sherouk Diab   ▢ Ahmed sayed            │
///   │                                                        │
///   │  Description text ... up to 150 chars then "See more"  │
///   │                                                        │
///   │  Links:  🔗 link 1   🔗 link 2                          │
///   │                                                        │
///   │  ┌──────────────────────┐  ┌─────────────────────────┐  │
///   │  │  Open task           │  │ 🟢 Due in 2 days        │  │ ← footer
///   │  └──────────────────────┘  └─────────────────────────┘  │
///   └────────────────────────────────────────────────────────┘
class SystemCard extends StatefulWidget {
  final MessageModel message;
  final int? currentUserId;

  /// Callback invoked when the user taps the "Open task" / "RSVP" button.
  final void Function(int taskId)? onOpenTask;
  final void Function(int meetingId, String rsvp)? onRsvpMeeting;

  // ─── Sprint P.1 — Inline approve / reject / reply from chat ────────
  // When provided, the card shows the appropriate green/red/blue button
  // row above the standard footer. Each callback receives the resolved
  // task id. Show only when the current user is the task's creator AND
  // the card is in a state that supports the action.
  final void Function(int taskId)? onApproveTask;
  final void Function(int taskId)? onRejectTask;
  /// Sprint R — creator (or owner / brand admin) acknowledges receipt of
  /// the deliverable from the assignee. Required step before approve/reject.
  final void Function(int taskId)? onReceiveTask;
  final void Function(int taskId)? onReplyClarification;

  // Sprint P.7 — set to true when a clarification_reply card already
  // exists for THIS clarification_request's task, so we hide the Reply
  // button (no double-answers).
  final bool clarificationAnswered;

  // A later card already received / decided this task → hide the buttons so
  // the creator can't receive twice or approve after already deciding.
  final bool alreadyReceived;
  final bool alreadyDecided;

  // True when rendered inside a CUSTOM (mixed-brand) room → show the client
  // chip on the card so you know which brand each task belongs to.
  final bool showBrand;

  const SystemCard({
    super.key,
    required this.message,
    this.currentUserId,
    this.onOpenTask,
    this.onRsvpMeeting,
    this.onApproveTask,
    this.onRejectTask,
    this.onReceiveTask,
    this.onReplyClarification,
    this.clarificationAnswered = false,
    this.alreadyReceived = false,
    this.alreadyDecided = false,
    this.showBrand = false,
  });

  @override
  State<SystemCard> createState() => _SystemCardState();
}

class _SystemCardState extends State<SystemCard> {
  bool _expandedDescription = false;

  @override
  Widget build(BuildContext context) {
    final spec = _specFor(widget.message.type);
    if (spec == null) return const SizedBox.shrink();

    final payload = widget.message.payload ?? const <String, dynamic>{};
    final isClarification = widget.message.type == MessageType.clarification ||
        widget.message.type == MessageType.clarificationReply;
    // Task-done now uses the same payload-driven design with a "To:
    // recipient" row, so we treat it like clarification for layout purposes.
    final isDone = widget.message.type == MessageType.taskDone;
    final isTask = widget.message.type == MessageType.taskCard ||
        isDone ||
        isClarification;

    // Resolve the task this card should navigate to for the CURRENT user.
    // If the user is one of the assignees we pick THEIR task id (since
    // task_ids[i] ↔ assignee_ids[i] in our bulk-create flow). Otherwise we
    // fall back to the primary task id so observers can still peek.
    final myTaskId = _resolveTaskIdForCurrentUser(payload);
    final canTap = isTask && myTaskId != null && widget.onOpenTask != null;

    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: spec.color.withValues(alpha: 0.25)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sprint S — Header now shows the Assigned to chip on the right.
          // The body no longer renders _Recipient/_Assignees beneath the
          // title since the chip already identifies whose task it is.
          _Header(spec: spec, payload: payload),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Title(payload: payload, fallback: widget.message.body, spec: spec),
                // Client chip — custom (mixed-brand) rooms only.
                if (widget.showBrand &&
                    (payload['brand_name'] as String?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2,),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: AppRadius.rPill,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sell_outlined,
                              size: 12, color: Color(0xFF4338CA),),
                          const SizedBox(width: 4),
                          Text(
                            payload['brand_name'] as String,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4338CA),),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (widget.message.type == MessageType.taskCard)
                  _PriorityChip(payload: payload),
                // Final completion summary — only on approved cards. Shows
                // created/approved dates, total duration, and who did it,
                // making the closing card clearly distinct from "received".
                if (widget.message.type == MessageType.taskDone &&
                    (payload['event'] as String?) == 'approved')
                  _ApprovedSummary(payload: payload),
                // Deliverables summary — the heart of the card. Shows the
                // requested outputs as chips + an overall progress bar.
                ..._deliverablesBlock(payload),
                ..._descriptionBlock(payload, isClarification),
                ..._imagesBlock(payload), // Sprint P.5 — inline image slider
                ..._linksBlock(payload),
                // Sprint S — Reply / Receive / Approve / Reject — they
                // appear at the bottom of the white body, above the footer.
                _BodyActions(
                  payload: payload,
                  messageType: widget.message.type,
                  currentUserId: widget.currentUserId,
                  taskIdForActions: myTaskId,
                  onApproveTask: widget.onApproveTask,
                  onRejectTask: widget.onRejectTask,
                  onReceiveTask: widget.onReceiveTask,
                  onReplyClarification: widget.onReplyClarification,
                  clarificationAnswered: widget.clarificationAnswered,
                  alreadyReceived: widget.alreadyReceived,
                  alreadyDecided: widget.alreadyDecided,
                ),
              ],
            ),
          ),
          _Footer(
            payload: payload,
            spec: spec,
            isTask: isTask,
            currentUserId: widget.currentUserId,
            onRsvpMeeting: widget.onRsvpMeeting,
            messageType: widget.message.type,
            showTapHint: canTap,
            // Sprint S — single Open task link in the footer for every
            // card type. Specialised labels (Review & approve, Open
            // reply, etc.) collapse to "Open task" so the footer reads
            // identically across the lifecycle.
            openButtonLabel: canTap ? 'Open task' : null,
            onOpenTask: canTap ? () => widget.onOpenTask!(myTaskId) : null,
            taskIdForActions: myTaskId,
            onApproveTask: widget.onApproveTask,
            onRejectTask: widget.onRejectTask,
            onReceiveTask: widget.onReceiveTask,
            onReplyClarification: widget.onReplyClarification,
            clarificationAnswered: widget.clarificationAnswered,
            createdAt: widget.message.createdAt,
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: canTap
          ? Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => widget.onOpenTask!(myTaskId),
                child: card,
              ),
            )
          : card,
    );
  }

  /// task_ids[i] aligns with assignee_ids[i] from createBulkTask. Use the
  /// current user's position to pick the right task. Fallback chain:
  ///   1. The task_id at our assignee_ids index.
  ///   2. primary_task_id.
  ///   3. Single 'task_id' field (legacy).
  ///   4. First entry of task_ids.
  int? _resolveTaskIdForCurrentUser(Map<String, dynamic> payload) {
    final me = widget.currentUserId;
    final taskIds =
        (payload['task_ids'] as List?)?.whereType<num>().map((e) => e.toInt()).toList();
    final assigneeIds = (payload['assignee_ids'] as List?)
        ?.whereType<num>()
        .map((e) => e.toInt())
        .toList();
    if (me != null && taskIds != null && assigneeIds != null) {
      final idx = assigneeIds.indexOf(me);
      if (idx >= 0 && idx < taskIds.length) return taskIds[idx];
    }
    if (payload['primary_task_id'] is num) {
      return (payload['primary_task_id'] as num).toInt();
    }
    if (payload['task_id'] is num) {
      return (payload['task_id'] as num).toInt();
    }
    if (taskIds != null && taskIds.isNotEmpty) return taskIds.first;
    return null;
  }

  /// Deliverables panel — the rich task summary the chat needs. Renders each
  /// requested output as a chip ("2× تصميم استوري"), an overall progress bar,
  /// and a done/total counter. Returns [] when the card has no deliverables.
  List<Widget> _deliverablesBlock(Map<String, dynamic> payload) {
    final raw = payload['deliverables'];
    if (raw is! List || raw.isEmpty) return const [];
    final items =
        raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    if (items.isEmpty) return const [];

    var totalQty = 0, totalDone = 0;
    for (final d in items) {
      totalQty += (d['qty'] as num?)?.toInt() ?? 0;
      totalDone += (d['done'] as num?)?.toInt() ?? 0;
    }
    final pct = totalQty > 0 ? (totalDone / totalQty).clamp(0.0, 1.0) : 0.0;
    const indigo = Color(0xFF4338CA);

    return [
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FF),
          borderRadius: AppRadius.rSm,
          border: Border.all(color: const Color(0xFFE3E6FF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 14, color: indigo,),
                const SizedBox(width: 6),
                const Text('Deliverables',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: indigo,),),
                const Spacer(),
                if (totalQty > 0)
                  Text('$totalDone/$totalQty',
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: indigo,),),
              ],
            ),
            if (totalQty > 0) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 5,
                  backgroundColor: const Color(0xFFE3E6FF),
                  valueColor: const AlwaysStoppedAnimation(indigo),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in items)
                  Builder(builder: (_) {
                    final qty = (d['qty'] as num?)?.toInt() ?? 1;
                    final done = (d['done'] as num?)?.toInt() ?? 0;
                    final label = (d['label'] as String?) ??
                        (d['type']?.toString() ?? '');
                    final complete = qty > 0 && done >= qty;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4,),
                      decoration: BoxDecoration(
                        color:
                            complete ? const Color(0xFFDCFCE7) : Colors.white,
                        borderRadius: AppRadius.rSm,
                        border: Border.all(
                            color: complete
                                ? const Color(0xFF86EFAC)
                                : const Color(0xFFE3E6FF),),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (complete)
                            const Padding(
                              padding: EdgeInsets.only(right: 3),
                              child: Icon(Icons.check,
                                  size: 12, color: Color(0xFF166534),),
                            ),
                          Text(
                            '${done > 0 ? '$done/$qty' : '$qty×'} $label',
                            textDirection: detectBidiDirection(label),
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: complete
                                    ? const Color(0xFF166534)
                                    : const Color(0xFF374151),),
                          ),
                        ],
                      ),
                    );
                  },),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _descriptionBlock(Map<String, dynamic> payload,
      [bool isClarification = false,]) {
    // For clarification cards the "description" is the question / answer text,
    // not the original task description. Fall back to the message body so old
    // payloads still render.
    String? raw;
    if (isClarification) {
      raw = (payload['clarification_reply'] as String?) ??
          (payload['clarification_text'] as String?) ??
          widget.message.body;
    } else {
      raw = payload['description'] as String?;
    }
    raw = raw?.trim();
    if (raw == null || raw.isEmpty) return const [];
    // Strip any auto-extracted URLs that we'll render separately as link chips.
    final body = raw.replaceAll(RegExp(r'\bhttps?://\S+'), '').trim();
    if (body.isEmpty) return const [];

    // Only NEW-task cards truncate long descriptions behind "See more" —
    // clarification Q/A, replies, done/received/approved cards always show
    // the FULL text (a cut-off question or answer is useless).
    final truncatable = widget.message.type == MessageType.taskCard;
    const limit = 150;
    final isLong = truncatable && body.length > limit;
    final shown = (_expandedDescription || !isLong)
        ? body
        : '${body.substring(0, limit).trimRight()}…';

    return [
      const SizedBox(height: 10),
      Text(
        shown,
        textDirection: detectBidiDirection(shown),
        style: const TextStyle(
          fontSize: 13.5,
          height: 1.35,
          color: AppColors.ink2,
        ),
      ),
      if (isLong)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: InkWell(
            onTap: () =>
                setState(() => _expandedDescription = !_expandedDescription),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                _expandedDescription ? 'See less' : 'See more',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.arenaBlue,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  /// Sprint P.5 — render the payload's images as a horizontal slider.
  /// Sources:
  ///   - payload['images']            — brief attachments (KIND_INITIAL)
  ///   - payload['completion_images'] — deliverables (KIND_COMPLETION)
  /// Mirrors the desktop chat card. Tapping an image opens it full-screen
  /// (handled inside [_TaskCardImageStrip]).
  List<Widget> _imagesBlock(Map<String, dynamic> payload) {
    final imgs = <Map<String, dynamic>>[];

    void absorb(dynamic raw) {
      if (raw is! List) return;
      for (final item in raw) {
        if (item is! Map) continue;
        final url = (item['url'] as String?) ?? '';
        if (url.isEmpty) continue;
        imgs.add({
          'url': _normalizeUrl(url),
          'name': (item['name'] as String?) ?? '',
        });
      }
    }

    absorb(payload['images']);
    absorb(payload['completion_images']);

    if (imgs.isEmpty) return const [];

    return [
      const SizedBox(height: 10),
      _TaskCardImageStrip(images: imgs),
    ];
  }

  /// Mobile-app-created tasks bake an absolute URL with `10.0.2.2:8000`
  /// host. When viewed elsewhere (real phone, another emulator) that host
  /// isn't reachable. Strip to the relative path so each client resolves
  /// against its own API base.
  String _normalizeUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAbsolutePath) return url;
    if (uri.scheme.isEmpty) return url;
    return uri.path + (uri.hasQuery ? '?${uri.query}' : '');
  }

  List<Widget> _linksBlock(Map<String, dynamic> payload) {
    final raw = payload['links'];
    if (raw is! List || raw.isEmpty) return const [];
    final links = raw
        .map((e) => e?.toString())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();
    if (links.isEmpty) return const [];

    return [
      const SizedBox(height: 10),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < links.length; i++)
            _LinkChip(label: 'Link ${i + 1}', url: links[i]),
        ],
      ),
    ];
  }

  _CardSpec? _specFor(String type) {
    switch (type) {
      case MessageType.taskCard:
        return const _CardSpec(
          icon: Icons.task_alt,
          color: AppColors.arenaBlue,
          label: 'New task',
        );
      case MessageType.taskDone:
        // Same type covers many sub-events distinguished by payload.event:
        //   completed (or null) → assignee submitted (waiting receipt)
        //   received            → creator acknowledged + reviewing
        //   approved            → final OK
        //   rejected            → sent back to assignee
        final payload = widget.message.payload ?? const <String, dynamic>{};
        final event = payload['event'] as String?;
        if (event == 'approved') {
          return const _CardSpec(
            icon: Icons.verified,
            // Royal violet — celebratory + clearly distinct from the green
            // "Done" card (they used to be the same color).
            color: Color(0xFF7C3AED),
            label: 'Task approved',
          );
        }
        if (event == 'rejected') {
          return const _CardSpec(
            icon: Icons.close,
            color: AppColors.arenaRed,
            label: 'Task rejected',
          );
        }
        if (event == 'received') {
          return const _CardSpec(
            icon: Icons.inbox,
            color: Color(0xFF6366F1), // indigo — distinct from green/blue/red
            label: 'Task received — in review',
          );
        }
        return const _CardSpec(
          icon: Icons.check_circle,
          color: AppColors.greenBorder,
          label: 'Task done — needs receipt',
        );
      case MessageType.meetingCard:
        return const _CardSpec(
          icon: Icons.event,
          color: AppColors.orangeBorder,
          label: 'Meeting',
        );
      case MessageType.clarification:
        return const _CardSpec(
          icon: Icons.help_outline,
          color: AppColors.warning,
          label: 'Clarification request',
        );
      case MessageType.clarificationReply:
        return const _CardSpec(
          icon: Icons.reply_all,
          color: AppColors.arenaBlue,
          label: 'Reply to clarification',
        );
      case MessageType.system:
        return const _CardSpec(
          icon: Icons.info_outline,
          color: AppColors.ink3,
          label: 'Notice',
        );
      default:
        return null;
    }
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final _CardSpec spec;
  final Map<String, dynamic> payload;
  const _Header({required this.spec, required this.payload});

  /// Pull the first assignee name + count of remaining from the payload.
  /// Tries `assignees[0]` (full object), then falls back to `assignee_name`
  /// or the recipient name (clarification / approval flows).
  ({String name, String? avatarUrl, int extra}) _firstAssignee() {
    final raw = payload['assignees'];
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map) {
        return (
          name: (first['name'] as String?) ?? '?',
          avatarUrl: first['avatar_url'] as String?,
          extra: raw.length - 1,
        );
      }
    }
    final fallbackName = (payload['assignee_name'] as String?) ??
        (payload['recipient_name'] as String?) ??
        '';
    return (
      name: fallbackName,
      avatarUrl: payload['recipient_avatar_url'] as String?,
      extra: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _firstAssignee();
    final showAssignee = a.name.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: spec.color,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          // LEFT — type icon + label
          Icon(spec.icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              spec.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ),
          // RIGHT — Sprint S — Assigned to chip pinned to the far right.
          // Shows the first assignee name + "+N" badge for the rest.
          if (showAssignee) ...[
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_outline,
                    size: 11, color: Colors.white70,),
                const SizedBox(width: 3),
                const Text(
                  'Assigned',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  constraints: const BoxConstraints(maxWidth: 130),
                  padding:
                      const EdgeInsets.only(left: 2, right: 8, top: 1, bottom: 1),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AssigneeAvatar(name: a.name, avatarUrl: a.avatarUrl),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: spec.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (a.extra > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '+${a.extra}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Mini avatar — uses the URL if available, otherwise a colored initial.
class _AssigneeAvatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  const _AssigneeAvatar({required this.name, required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final init =
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final url = avatarUrl;
    const size = 16.0;
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: (url != null && url.isNotEmpty)
            ? AuthedNetworkImage(url: url, fit: BoxFit.cover)
            : Container(
                color: AppColors.arenaBlue,
                alignment: Alignment.center,
                child: Text(
                  init,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final Map<String, dynamic> payload;
  final String? fallback;
  final _CardSpec spec;
  const _Title(
      {required this.payload, required this.fallback, required this.spec,});

  @override
  Widget build(BuildContext context) {
    final title = (payload['task_title'] as String?) ??
        (payload['title'] as String?) ??
        fallback ??
        spec.label;
    return Text(
      title,
      textDirection: detectBidiDirection(title),
      style: const TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
        height: 1.25,
      ),
    );
  }
}

class _Assignees extends StatelessWidget {
  final Map<String, dynamic> payload;
  const _Assignees({required this.payload});

  List<({int? id, String name, String? avatarUrl})> _list() {
    final raw = payload['assignees'];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map((m) => (
                id: (m['id'] is num) ? (m['id'] as num).toInt() : null,
                name: (m['name'] as String? ?? '').trim(),
                avatarUrl: m['avatar_url'] as String?,
              ),)
          .where((r) => r.name.isNotEmpty)
          .toList();
    }
    // Single-assignee fallback from old payload shape.
    final single = payload['assignee_name'] ?? payload['assignee'];
    if (single is String && single.isNotEmpty) {
      return [(id: null, name: single, avatarUrl: null)];
    }
    return const [];
  }

  Color _initialColor(String name) {
    final hues = [
      AppColors.arenaBlue,
      const Color(0xFFEC4899),
      const Color(0xFF10B981),
      const Color(0xFF8B5CF6),
      const Color(0xFFF59E0B),
      const Color(0xFF06B6D4),
      AppColors.arenaRed,
    ];
    final hash = name.codeUnits.fold<int>(0, (a, c) => a + c);
    return hues[hash.abs() % hues.length];
  }

  @override
  Widget build(BuildContext context) {
    final list = _list();
    if (list.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Assigned to',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink3,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in list)
                Container(
                  padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
                  decoration: BoxDecoration(
                    color: _initialColor(a.name).withValues(alpha: 0.10),
                    borderRadius: AppRadius.rLg,
                    border: Border.all(
                      color: _initialColor(a.name).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(
                        name: a.name,
                        avatarUrl: a.avatarUrl,
                        size: 20,
                        backgroundColor: _initialColor(a.name),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        a.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _initialColor(a.name),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "To: NAME" chip used by clarification request + reply cards. Shares the
/// avatar/initials styling of the assignee chip so the visual language is
/// consistent.
class _Recipient extends StatelessWidget {
  final Map<String, dynamic> payload;
  const _Recipient({required this.payload});

  Color _initialColor(String name) {
    final hues = [
      AppColors.arenaBlue,
      const Color(0xFFEC4899),
      const Color(0xFF10B981),
      const Color(0xFF8B5CF6),
      const Color(0xFFF59E0B),
      const Color(0xFF06B6D4),
      AppColors.arenaRed,
    ];
    final hash = name.codeUnits.fold<int>(0, (a, c) => a + c);
    return hues[hash.abs() % hues.length];
  }

  @override
  Widget build(BuildContext context) {
    final name = (payload['recipient_name'] as String?)?.trim();
    if (name == null || name.isEmpty) return const SizedBox.shrink();
    final color = _initialColor(name);
    final avatarUrl = payload['recipient_avatar_url'] as String?;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'To',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink3,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: AppRadius.rLg,
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              UserAvatar(
                name: name,
                avatarUrl: avatarUrl,
                size: 20,
                backgroundColor: color,
              ),
              const SizedBox(width: 6),
              Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _open,
      borderRadius: AppRadius.rLg,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.arenaBlueLight,
          borderRadius: AppRadius.rLg,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link, size: 14, color: AppColors.arenaBlue),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.arenaBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small colour-coded priority pill shown under a task card's title.
class _PriorityChip extends StatelessWidget {
  final Map<String, dynamic> payload;
  const _PriorityChip({required this.payload});

  @override
  Widget build(BuildContext context) {
    final p = payload['priority'];
    if (p is! String) return const SizedBox.shrink();
    final ({Color bg, Color fg, String label})? c = switch (p) {
      'urgent' => (bg: const Color(0xFFFEE2E2), fg: const Color(0xFFB91C1C), label: 'Urgent'),
      'high' => (bg: const Color(0xFFFFEDD5), fg: const Color(0xFF9A3412), label: 'High'),
      'medium' => (bg: const Color(0xFFFEF3C7), fg: const Color(0xFF92400E), label: 'Medium'),
      'low' => (bg: const Color(0xFFD1FAE5), fg: const Color(0xFF065F46), label: 'Low'),
      _ => null,
    };
    if (c == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag, size: 11, color: c.fg),
            const SizedBox(width: 4),
            Text(
              c.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c.fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final Map<String, dynamic> payload;
  final _CardSpec spec;
  final bool isTask;
  final int? currentUserId;
  final void Function(int meetingId, String rsvp)? onRsvpMeeting;
  final String messageType;
  final bool showTapHint;
  final String? openButtonLabel;
  final VoidCallback? onOpenTask;
  // Sprint P.7 — inline action chips
  final int? taskIdForActions;
  final void Function(int taskId)? onApproveTask;
  final void Function(int taskId)? onRejectTask;
  /// Sprint R — creator (or owner / brand admin) acknowledges receipt of
  /// the deliverable from the assignee. Required step before approve/reject.
  final void Function(int taskId)? onReceiveTask;
  final void Function(int taskId)? onReplyClarification;
  final bool clarificationAnswered;
  /// Sprint S — the message send-time, pinned to the right of the footer.
  final DateTime? createdAt;

  const _Footer({
    required this.payload,
    required this.spec,
    required this.isTask,
    required this.currentUserId,
    required this.onRsvpMeeting,
    required this.messageType,
    required this.showTapHint,
    this.openButtonLabel,
    this.onOpenTask,
    this.taskIdForActions,
    this.onApproveTask,
    this.onRejectTask,
    this.onReceiveTask,
    this.onReplyClarification,
    this.clarificationAnswered = false,
    this.createdAt,
  });

  // Sprint S — action-visibility getters moved to _BodyActions widget
  // since the action buttons are now rendered inside the body, not the
  // footer.

  ({Color bg, Color fg, String label, IconData icon})? _dueChip() {
    final raw = payload['due_at'];
    if (raw is! String || raw.isEmpty) return null;
    final due = DateTime.tryParse(raw);
    if (due == null) return null;
    final local = due.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(local.year, local.month, local.day);
    final daysLeft = dueDay.difference(today).inDays;

    final Color bg, fg;
    final String label;
    if (daysLeft < 0) {
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
    return (bg: bg, fg: fg, label: label, icon: Icons.event);
  }

  Widget _meetingFooter(BuildContext context) {
    final meetingId = payload['meeting_id'];
    if (meetingId is! int || onRsvpMeeting == null) {
      return const SizedBox.shrink();
    }
    Widget btn(String value, String label, Color color) => OutlinedButton(
          onPressed: () => onRsvpMeeting!(meetingId, value),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          ),
          child: Text(label, style: const TextStyle(fontSize: 11)),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          btn('accepted', 'Accept', AppColors.greenBorder),
          const SizedBox(width: 6),
          btn('tentative', 'Maybe', AppColors.warning),
          const SizedBox(width: 6),
          btn('declined', 'Decline', AppColors.arenaRed),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (messageType == MessageType.meetingCard) {
      return _meetingFooter(context);
    }
    if (!isTask) return const SizedBox.shrink();

    final due = _dueChip();

    // Sprint S — Unified footer:
    //   LEFT   → Open task link
    //   CENTER → Deadline chip (New Task card only)
    //   RIGHT  → message send-time
    // Action buttons (Reply / Receive / Approve / Reject) have moved
    // out — they're rendered by _BodyActions inside the white body
    // section, above this footer.
    final showOpen = onOpenTask != null;
    final showDeadline = messageType == MessageType.taskCard && due != null;
    final timeLabel = createdAt != null
        ? DateFormat('h:mm a').format(createdAt!.toLocal())
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFEEF0F2), width: 1),
        ),
      ),
      child: Row(
        children: [
          if (showOpen)
            InkWell(
              onTap: onOpenTask,
              borderRadius: AppRadius.rXs,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_forward,
                        size: 13, color: spec.color,),
                    const SizedBox(width: 4),
                    Text(
                      'Open task',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: spec.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (showDeadline) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: due.bg,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule, size: 11, color: due.fg),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Deadline: ${due.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: due.fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ] else
            const Spacer(),
          if (timeLabel != null)
            Text(
              timeLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
        ],
      ),
    );
  }
}

/// Sprint S — Action buttons rendered as a row at the bottom of the
/// white body, just above the footer separator. Replaces the inline
/// chips that used to sit in the footer next to Open.
///
/// Visible only for the creator on cards where the lifecycle expects
/// an action:
///   - clarification_request  → Reply to clarification
///   - task_done (completed)  → Mark as received
///   - task_done (received)   → Approve + Reject
class _BodyActions extends StatelessWidget {
  final Map<String, dynamic> payload;
  final String messageType;
  final int? currentUserId;
  final int? taskIdForActions;
  final void Function(int taskId)? onApproveTask;
  final void Function(int taskId)? onRejectTask;
  final void Function(int taskId)? onReceiveTask;
  final void Function(int taskId)? onReplyClarification;
  final bool clarificationAnswered;
  final bool alreadyReceived;
  final bool alreadyDecided;

  const _BodyActions({
    required this.payload,
    required this.messageType,
    required this.currentUserId,
    required this.taskIdForActions,
    required this.onApproveTask,
    required this.onRejectTask,
    required this.onReceiveTask,
    required this.onReplyClarification,
    required this.clarificationAnswered,
    this.alreadyReceived = false,
    this.alreadyDecided = false,
  });

  bool get _amCreator {
    final c = (payload['creator_id'] as num?)?.toInt();
    return c != null && c == currentUserId;
  }

  bool get _showReply =>
      taskIdForActions != null &&
      onReplyClarification != null &&
      messageType == MessageType.clarification &&
      !clarificationAnswered &&
      _amCreator;

  bool get _showReceive {
    if (taskIdForActions == null || onReceiveTask == null) return false;
    if (messageType != MessageType.taskDone) return false;
    final ev = payload['event'] as String?;
    if (ev != null && ev != 'completed') return false;
    // Already received by a later card → hide (no double-receive).
    if (alreadyReceived) return false;
    return _amCreator;
  }

  bool get _showApproveReject {
    if (taskIdForActions == null || onApproveTask == null) return false;
    if (messageType != MessageType.taskDone) return false;
    if ((payload['event'] as String?) != 'received') return false;
    // Already approved/rejected by a later card → hide (no double-decide).
    if (alreadyDecided) return false;
    return _amCreator;
  }

  /// "✓ Received" / "✓ Reviewed" label shown in place of a button once the
  /// action was already taken (so the card isn't empty or actionable).
  String? get _doneLabel {
    if (messageType != MessageType.taskDone || !_amCreator) return null;
    final ev = payload['event'] as String?;
    if ((ev == null || ev == 'completed') && alreadyReceived) return 'Received';
    if (ev == 'received' && alreadyDecided) return 'Reviewed';
    return null;
  }

  Widget _btn({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.rXs,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.rXs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: fg,),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final any = _showReply || _showReceive || _showApproveReject;
    final doneLabel = _doneLabel;
    if (!any && doneLabel == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (doneLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.greenBg,
                borderRadius: AppRadius.rXs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check, size: 13, color: Color(0xFF065F46)),
                  const SizedBox(width: 5),
                  Text(doneLabel,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF065F46),),),
                ],
              ),
            ),
          if (_showReply)
            _btn(
              icon: Icons.reply,
              label: 'Reply to clarification',
              bg: AppColors.arenaBlue,
              fg: Colors.white,
              onTap: () => onReplyClarification!(taskIdForActions!),
            ),
          if (_showReceive)
            _btn(
              icon: Icons.inbox,
              label: 'Mark as received',
              bg: const Color(0xFF6366F1),
              fg: Colors.white,
              onTap: () => onReceiveTask!(taskIdForActions!),
            ),
          if (_showApproveReject) ...[
            _btn(
              icon: Icons.check,
              label: 'Approve',
              bg: AppColors.greenBorder,
              fg: Colors.white,
              onTap: () => onApproveTask!(taskIdForActions!),
            ),
            _btn(
              icon: Icons.close,
              label: 'Reject',
              bg: AppColors.redBg,
              fg: AppColors.arenaRed,
              onTap: () => onRejectTask!(taskIdForActions!),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardSpec {
  final IconData icon;
  final Color color;
  final String label;
  const _CardSpec({
    required this.icon,
    required this.color,
    required this.label,
  });
}

/// Sprint P.5 — horizontal image slider for task cards. Each thumb opens
/// a full-screen lightbox with pinch-zoom.
class _TaskCardImageStrip extends StatelessWidget {
  final List<Map<String, dynamic>> images;
  const _TaskCardImageStrip({required this.images});

  void _openLightbox(BuildContext context, int initialIndex) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ImageLightbox(images: images, initialIndex: initialIndex),
    ),);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final img = images[i];
          final url = img['url'] as String;
          return ClipRRect(
            borderRadius: AppRadius.rSm,
            child: GestureDetector(
              onTap: () => _openLightbox(context, i),
              child: SizedBox(
                width: 90,
                height: 90,
                child: AuthedNetworkImage(
                  url: url,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Full-screen image viewer with horizontal swipe + pinch-zoom + download
/// button. Used by [_TaskCardImageStrip] AND can be reused elsewhere via
/// `Navigator.push`.
class _ImageLightbox extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> images;
  final int initialIndex;
  const _ImageLightbox({required this.images, this.initialIndex = 0});

  @override
  ConsumerState<_ImageLightbox> createState() => _ImageLightboxState();
}

class _ImageLightboxState extends ConsumerState<_ImageLightbox> {
  late final PageController _ctrl;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _ctrl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Sprint Q.2 — fetch via authed Dio + open with OS handler (so on
  /// Android it lands in the gallery / system file viewer instead of
  /// a 401 from the browser).
  Future<void> _download() async {
    final img = widget.images[_index];
    final url = img['url'] as String;
    final name = (img['name'] as String?) ?? '';
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(attachmentDownloaderProvider).downloadAndOpen(
            url,
            filename: name.isEmpty ? null : name,
          );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  Future<void> _share() async {
    final img = widget.images[_index];
    final url = img['url'] as String;
    final name = (img['name'] as String?) ?? '';
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(attachmentDownloaderProvider).downloadAndShare(
            url,
            filename: name.isEmpty ? null : name,
          );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '${_index + 1} / ${widget.images.length}',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _share,
            tooltip: 'Share',
          ),
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: _download,
            tooltip: 'Download',
          ),
        ],
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (ctx, i) {
          final url = widget.images[i]['url'] as String;
          return InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: AuthedNetworkImage(
                url: url,
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Final completion summary shown ONLY on approved cards — created date,
/// approved date, total duration, and who completed the task. Makes the
/// closing card clearly distinct from the "received" card.
class _ApprovedSummary extends StatelessWidget {
  final Map<String, dynamic> payload;
  const _ApprovedSummary({required this.payload});

  DateTime? _parse(String? iso) =>
      iso == null ? null : DateTime.tryParse(iso)?.toLocal();

  String _fmt(DateTime d) => DateFormat('MMM d, yyyy · hh:mm a').format(d);

  String? _duration(DateTime? from, DateTime? to) {
    if (from == null || to == null) return null;
    final diff = to.difference(from);
    if (diff.inMinutes < 1) return 'less than a minute';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final mins = diff.inMinutes % 60;
    final parts = <String>[
      if (days > 0) '${days}d',
      if (hours > 0) '${hours}h',
      if (days == 0 && mins > 0) '${mins}m',
    ];
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final created = _parse(payload['task_created_at'] as String?);
    final approved = _parse(payload['approved_at'] as String?);
    final duration = (payload['duration_human'] as String?) ??
        _duration(created, approved);
    final by = (payload['completed_by'] as String?) ??
        (payload['assignee_name'] as String?);

    final rows = <(String, String)>[
      if (created != null) ('📅', 'Created: ${_fmt(created)}'),
      if (approved != null) ('✅', 'Approved: ${_fmt(approved)}'),
      if (duration != null) ('⏱️', 'Took: $duration'),
      if (by != null && by.isNotEmpty) ('👤', 'Completed by: $by'),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF), // violet tint — matches the card
        borderRadius: AppRadius.rSm,
        border: Border.all(color: const Color(0xFFDDD6FE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Text(
                '${r.$1} ${r.$2}',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Color(0xFF065F46),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
