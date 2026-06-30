import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/errors/api_exception.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/push/active_chat_tracker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/text_direction_util.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../tasks/presentation/widgets/group_task_summary_sheet.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../tasks/presentation/controllers/tasks_providers.dart';
import '../../data/models/message_model.dart';
import '../controllers/chat_providers.dart';
import '../controllers/groups_controller.dart';
import '../controllers/messages_controller.dart';
import '../controllers/typing_controller.dart';
import '../widgets/attachment_picker_sheet.dart';
import '../widgets/composer.dart';
import '../widgets/create_task_from_message_sheet.dart';
import '../widgets/message_actions_sheet.dart';
import '../widgets/seen_by_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/reply_banner.dart';
import '../widgets/system_card.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/voice_preview.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  final int groupId;
  const ConversationScreen({super.key, required this.groupId});

  @override
  ConsumerState<ConversationScreen> createState() =>
      _ConversationScreenState();
}

/// Sprint P.5 — shared RouteObserver so the chat screen can detect when
/// it's re-shown after the user pops back from task detail or any other
/// pushed route. Registered with go_router via `observers:` so every
/// navigation pops through it.
final ConversationRouteObserver chatRouteObserver = ConversationRouteObserver();
class ConversationRouteObserver extends RouteObserver<PageRoute<dynamic>> {}

class _ConversationScreenState extends ConsumerState<ConversationScreen>
    with RouteAware {
  final _scrollController = ScrollController();
  final _composerFocus = FocusNode();
  bool _didInitialScroll = false;
  int _lastSeenLength = 0;
  // Per-message keys so we can scroll to a message tapped in the pinned list.
  final Map<int, GlobalKey> _msgKeys = {};

  /// Message we're currently replying to, or null.
  MessageModel? _replyingTo;

  /// Sprint P.2 — message we're currently editing, or null. When set, the
  /// composer pre-fills with `_editingMessage.body`, the send button calls
  /// the edit endpoint instead of sendText, and a banner shows above the
  /// composer.
  MessageModel? _editingMessage;

  /// Pending voice recording awaiting user confirmation (WhatsApp-style).
  ({File file, Duration duration})? _pendingVoice;
  bool _sendingVoice = false;

  @override
  void initState() {
    super.initState();
    // Tell the push service to suppress notifications for this group while
    // the chat is on screen.
    ActiveChatTracker.enter(widget.groupId);

    // Infinite scroll-back: pull older messages as the user nears the top.
    _scrollController.addListener(_onScrollLoadOlder);

    // If the messages provider ALREADY holds data (e.g. this chat was open
    // and a notification tap pushed a second copy, or the provider was kept
    // alive), the "first load" ref.listen below never fires — so without
    // this the screen opened mid-list instead of at the latest message.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didInitialScroll) return;
      final existing =
          ref.read(messagesControllerProvider(widget.groupId)).valueOrNull;
      if (existing != null) {
        _lastSeenLength = existing.length;
        _didInitialScroll = true;
        _jumpToBottomNextFrame(force: true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      chatRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    chatRouteObserver.unsubscribe(this);
    ActiveChatTracker.leave(widget.groupId);
    _scrollController.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  /// Fires when the user pops back FROM a pushed route INTO this screen
  /// (e.g. closing task detail). Auto-jump to the latest message so the
  /// user always lands at the newest activity (Sprint P.5).
  @override
  void didPopNext() {
    super.didPopNext();
    _jumpToBottomNextFrame(force: true);
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;
    return (max - current) < 200;
  }

  bool _loadingOlderLocal = false;

  /// When the user scrolls near the TOP, pull an older page and prepend it,
  /// then re-anchor the scroll so the list doesn't jump (seamless history).
  void _onScrollLoadOlder() {
    if (!_scrollController.hasClients || _loadingOlderLocal) return;
    final pos = _scrollController.position;
    if (pos.pixels > 300) return; // not near the top yet

    final notifier =
        ref.read(messagesControllerProvider(widget.groupId).notifier);
    if (!notifier.hasMoreOlder) return;

    _loadingOlderLocal = true;
    final beforeMax = pos.maxScrollExtent;
    final beforePixels = pos.pixels;

    notifier.loadOlder().then((added) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients && added > 0) {
          final afterMax = _scrollController.position.maxScrollExtent;
          // Older content was prepended above → shift down by the delta so the
          // same message stays under the user's eyes.
          final target = beforePixels + (afterMax - beforeMax);
          _scrollController.jumpTo(target.clamp(0.0, afterMax));
        }
        _loadingOlderLocal = false;
      });
    }).catchError((_) {
      _loadingOlderLocal = false;
    });
  }

  void _jumpToBottomNextFrame({bool force = false, VoidCallback? onDone}) {
    // Some messages (task cards, meeting cards, images) have variable height
    // that's not measured until they actually render. A single jumpTo(max)
    // only reaches the bottom of what's been laid out so far — leaving the
    // user a few items short of the true end. To handle this we retry across
    // several frames, jumping again whenever the maxScrollExtent grows.
    double lastMax = -1;
    int retries = 0;
    const maxRetries = 12;

    void attempt() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_scrollController.hasClients) {
          if (retries++ < maxRetries) {
            Future.delayed(const Duration(milliseconds: 30), attempt);
          }
          return;
        }
        try {
          if (!force && !_isNearBottom()) {
            onDone?.call();
            return;
          }
          final max = _scrollController.position.maxScrollExtent;
          if (max > _scrollController.position.pixels + 1) {
            _scrollController.jumpTo(max);
          }
          // Did the list extent grow this frame? If yes, layout hasn't
          // settled — keep checking. Once two consecutive frames return the
          // same max, we're done.
          if (max != lastMax && retries++ < maxRetries) {
            lastMax = max;
            Future.delayed(const Duration(milliseconds: 30), attempt);
          } else {
            onDone?.call();
          }
        } catch (_) {
          if (retries++ < maxRetries) {
            Future.delayed(const Duration(milliseconds: 30), attempt);
          }
        }
      });
    }
    attempt();
  }

  Future<void> _onLongPress(MessageModel message, bool isMine) async {
    if (message.isDeleted) return; // no actions on a removed message
    final notifier =
        ref.read(messagesControllerProvider(widget.groupId).notifier);
    final myId = ref.read(authControllerProvider).valueOrNull?.id ?? 0;

    final action = await MessageActionsSheet.show(
      context,
      message: message,
      isMine: isMine,
      myUserId: myId,
      onReact: (emoji) => notifier.react(message.id, emoji),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case MessageAction.pin:
        final pinned = await notifier.pin(message.id);
        if (mounted) _showToast(pinned ? 'Pinned' : 'Unpinned');
        break;
      case MessageAction.reply:
        setState(() => _replyingTo = message);
        _composerFocus.requestFocus();
        break;
      case MessageAction.createTask:
        await _openCreateTaskSheet(message);
        break;
      case MessageAction.markRed:
        await _runAction(() => notifier.markRed(message.id), 'Marked red');
        break;
      case MessageAction.markGreen:
        await _runAction(
            () => notifier.markGreen(message.id), 'Marked green',);
        break;
      case MessageAction.revert:
        await _runAction(() => notifier.revert(message.id), 'Mark cleared');
        break;
      case MessageAction.copy:
        _showToast('Copied');
        break;
      case MessageAction.share:
        await _shareMessage(message);
        break;
      case MessageAction.seenBy:
        await SeenBySheet.show(context, ref, message);
        break;
      case MessageAction.edit:
        setState(() {
          _editingMessage = message;
          _replyingTo = null; // edit and reply are mutually exclusive
        });
        _composerFocus.requestFocus();
        break;
      case MessageAction.delete:
        await _confirmAndDelete(message);
        break;
    }
  }

  Future<void> _openCreateTaskSheet(
    MessageModel message, {
    int? initialAssigneeId,
  }) async {
    final groupsState = ref.read(groupsControllerProvider).valueOrNull;
    final group =
        (groupsState ?? const []).where((g) => g.id == widget.groupId).firstOrNull;
    if (group == null) {
      _showToast('Chat not loaded yet, try again');
      return;
    }
    // A 1-on-1 chat lives under the "Direct Messages" sentinel brand — treat it
    // as private so the task creator defaults to "Private" with a brand slider.
    // CUSTOM groups (brainstorming rooms) also need the brand slider: their
    // tasks MUST belong to a client (enforced server-side), and the card is
    // mirrored back into this room.
    final isDm = group.brand?.slug == 'direct-messages' ||
        group.brand?.name == 'Direct Messages';
    final isCustom = group.brand?.slug == 'custom-groups' || group.isCustom;
    final created = await CreateTaskFromMessageSheet.show(
      context,
      sourceMessage: message,
      groupId: widget.groupId,
      initialBrandId: (isDm || isCustom) ? null : group.brand?.id,
      isDirectChat: isDm || isCustom,
      requireBrand: isCustom, // custom rooms: a brand is mandatory
      initialAssigneeId: initialAssigneeId,
    );
    // The realtime stream delivers the card to everyone — but for the CREATOR
    // the broadcast can race the sheet-close/navigation, so it sometimes only
    // showed after leaving + re-entering. Refresh locally on success so the
    // creator sees their new task card instantly too.
    if (created == true && mounted) {
      ref.read(messagesControllerProvider(widget.groupId).notifier).refresh();
    }
  }

  /// Owners / account managers / department managers get the live task-summary
  /// board button in the chat header.
  bool _canSeeTaskSummary() {
    final me = ref.read(authControllerProvider).valueOrNull;
    if (me == null) return false;
    return me.isOwner ||
        me.teamRole == 'owner' ||
        me.teamRole == 'account_manager' ||
        me.teamRole == 'department_manager';
  }

  GlobalKey _keyFor(int id) => _msgKeys.putIfAbsent(id, () => GlobalKey());

  /// Jump to a message, loading older pages first if it isn't in memory yet.
  ///
  /// The chat list is a lazy `ListView.builder` without keep-alives, so a
  /// message that's far off-screen has no built context. We first make sure the
  /// message is loaded into state, then estimate-jump to its position to force
  /// the surrounding rows to build, then fine-tune with `ensureVisible`.
  Future<void> _scrollToMessage(int id) async {
    final notifier =
        ref.read(messagesControllerProvider(widget.groupId).notifier);

    // 1) Make sure the message exists in local state (page back if needed).
    if (_msgKeys[id]?.currentContext == null) {
      final present = await notifier.ensureLoaded(id);
      if (!mounted) return;
      if (!present) {
        _showToast('Message not available');
        return;
      }
      // Let the list rebuild with the newly loaded messages.
      await Future.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
    }

    // 2) Up to a few passes: if built → ensureVisible; else estimate-jump.
    for (var attempt = 0; attempt < 6; attempt++) {
      final ctx = _msgKeys[id]?.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.4,
        );
        return;
      }
      final messages =
          ref.read(messagesControllerProvider(widget.groupId)).valueOrNull ??
              const [];
      final idx = messages.indexWhere((m) => m.id == id);
      if (idx >= 0 && _scrollController.hasClients) {
        final max = _scrollController.position.maxScrollExtent;
        final target = max * (idx / (messages.length).clamp(1, 1 << 30));
        _scrollController.jumpTo(target.clamp(0.0, max));
      }
      await Future.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
    }
  }

  /// Header pin icon → bottom sheet listing pinned messages; tap one to jump.
  Future<void> _showPinnedSheet() async {
    List<MessageModel> pins;
    try {
      pins = await ref.read(chatRepositoryProvider).listPins(widget.groupId);
    } catch (_) {
      if (mounted) _showToast('Could not load pinned messages');
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.push_pin, size: 18, color: Color(0xFFEF4444)),
                  SizedBox(width: 8),
                  Text('Pinned messages',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),),
                ],
              ),
            ),
            const Divider(height: 1),
            if (pins.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text('No pinned messages yet',
                    style: TextStyle(color: AppColors.ink3),),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: pins.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = pins[i];
                    return ListTile(
                      leading: UserAvatar(
                        name: p.sender?.name ?? '?',
                        avatarUrl: p.sender?.avatarUrl,
                        size: 36,
                      ),
                      title: Text(p.sender?.name ?? 'Unknown',
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600,),),
                      subtitle: Text(
                        (p.body ?? '').trim().isEmpty
                            ? '📎 Attachment'
                            : p.body!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _scrollToMessage(p.id);
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Tapped a sender's name → small popup with "Private chat" + "Add task".
  Future<void> _showPersonActions(MessageModel message) async {
    final sender = message.sender;
    if (sender == null) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  UserAvatar(
                    name: sender.name,
                    avatarUrl: sender.avatarUrl,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      sender.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline,
                  color: AppColors.arenaBlue,),
              title: const Text('Private chat'),
              onTap: () => Navigator.pop(sheetContext, 'dm'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.add_task, color: AppColors.arenaBlue),
              title: const Text('Add task'),
              onTap: () => Navigator.pop(sheetContext, 'task'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (action == 'dm') {
      await _openPrivateChat(sender.id);
    } else if (action == 'task') {
      await _openCreateTaskSheet(message, initialAssigneeId: sender.id);
    }
  }

  /// Find-or-create the 1-on-1 thread with [userId] then navigate into it.
  Future<void> _openPrivateChat(int userId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final thread = await ref.read(chatRepositoryProvider).openDm(userId);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // dismiss loader
      // Refresh the chats list so the (possibly new) DM thread shows up there.
      ref.invalidate(groupsControllerProvider);
      context.push('/chat/${thread.id}');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // dismiss loader
      _showToast('Could not open private chat');
    }
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String successMessage,
  ) async {
    try {
      await action();
      if (mounted) _showToast(successMessage);
    } catch (e) {
      if (!mounted) return;
      final msg = switch (e) {
        ApiException(:final message) => message,
        _ => e.toString(),
      };
      _showToast(msg, error: true);
    }
  }

  void _showToast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: error ? AppColors.arenaRed : null,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _sendText(String body, List<int> mentions) async {
    // Sprint P.2 — composer is in edit mode → PATCH instead of POST.
    if (_editingMessage != null) {
      final editing = _editingMessage!;
      try {
        await ref
            .read(messagesControllerProvider(widget.groupId).notifier)
            .editMessage(editing.id, body);
        if (!mounted) return;
        setState(() => _editingMessage = null);
        _showToast('Message edited');
      } catch (e) {
        if (!mounted) return;
        final msg = switch (e) {
          ApiException(:final message) => message,
          _ => e.toString(),
        };
        _showToast('Edit failed: $msg', error: true);
      }
      return;
    }
    final replyId = _replyingTo?.id;
    await ref
        .read(messagesControllerProvider(widget.groupId).notifier)
        .sendText(
          body,
          replyToId: replyId,
          mentions: mentions.isEmpty ? null : mentions,
        );
    if (!mounted) return;
    if (_replyingTo != null) setState(() => _replyingTo = null);
    // Always scroll to my own outgoing message (force = true bypasses the
    // "near bottom" gate used for other people's incoming messages).
    _jumpToBottomNextFrame(force: true);
  }

  Future<void> _pickAndSendAttachment() async {
    final picked = await AttachmentPickerSheet.show(context);
    if (picked.isEmpty || !mounted) return;

    final replyId = _replyingTo?.id;
    final total = picked.length;
    var failed = 0;

    for (var i = 0; i < total; i++) {
      if (!mounted) return;
      _showToast(total == 1 ? 'Uploading...' : 'Uploading ${i + 1}/$total...');
      try {
        await ref
            .read(messagesControllerProvider(widget.groupId).notifier)
            .sendFile(
              picked[i].file,
              // Only the FIRST file carries the reply reference.
              replyToId: i == 0 ? replyId : null,
            );
        if (!mounted) return;
        _jumpToBottomNextFrame(force: true);
      } catch (e) {
        failed++;
        if (!mounted) return;
        final msg = switch (e) {
          ApiException(:final message) => message,
          _ => e.toString(),
        };
        _showToast('Failed (${i + 1}/$total): $msg', error: true);
      }
    }

    if (!mounted) return;
    if (_replyingTo != null) setState(() => _replyingTo = null);
    if (failed == 0) {
      _showToast(total == 1 ? 'Sent' : 'Sent $total files');
    }
  }

  /// Sprint Q.1 — push the message through the native share sheet
  /// (WhatsApp, Mail, Drive, …).
  ///
  /// Three paths:
  ///   - **Text + body**            → share the plain text.
  ///   - **Image / file / voice**   → download via Dio with the bearer
  ///     token, then `Share.shareXFiles` so the receiving app gets the
  ///     actual binary, not a URL it can't authenticate against.
  ///   - **Mixed (caption + file)** → share file with body as text.
  Future<void> _shareMessage(MessageModel message) async {
    final downloader = ref.read(attachmentDownloaderProvider);
    final body = (message.body ?? '').trim();
    final attachments = message.attachments;

    try {
      if (attachments.isEmpty) {
        if (body.isEmpty) {
          _showToast('Nothing to share', error: true);
          return;
        }
        await downloader.shareText(body);
        return;
      }

      // One file → toast + share. Many → download all in parallel.
      _showToast('Preparing to share…');
      final files = await Future.wait(attachments.map((a) async {
        final f = await downloader.download(
          a.downloadUrl,
          filename: a.originalName,
        );
        return XFile(f.path);
      }),);
      await Share.shareXFiles(
        files,
        text: body.isEmpty ? null : body,
      );
    } catch (e) {
      if (!mounted) return;
      _showToast('Share failed: $e', error: true);
    }
  }

  Future<void> _confirmAndDelete(MessageModel m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message'),
        content: const Text('Delete this message? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.arenaRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final notifier =
        ref.read(messagesControllerProvider(widget.groupId).notifier);
    await _runAction(
      () => notifier.deleteMessage(m.id),
      'Message deleted',
    );
  }

  // ─── Sprint P.1 — inline task actions from chat system cards ────────

  Future<void> _approveTaskFromChat(int taskId) async {
    try {
      await ref.read(tasksRepositoryProvider).approve(taskId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task approved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approve failed: $e')),
      );
    }
  }

  /// Sprint R — Receive flow with an optional note ("Sent to client X").
  /// Opens a small bottom sheet, lets the user type a note, then POSTs
  /// to /tasks/{id}/receive. After success the realtime stream picks up
  /// the new "Task received" system card automatically.
  Future<void> _receiveTaskFromChat(int taskId) async {
    final ctrl = TextEditingController();
    final result = await showModalBottomSheet<({bool confirmed, String note})>(
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
                'You acknowledge the deliverable. Add a note if you want '
                "(e.g. \"sent to client for review\") — it'll show in the "
                'chat card. Approve/Reject becomes available next.',
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
                  ctx,
                  (confirmed: true, note: ctrl.text.trim()),
                ),
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
    if (result == null || !result.confirmed) return;
    try {
      await ref
          .read(tasksRepositoryProvider)
          .receive(taskId, note: result.note.isEmpty ? null : result.note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as received')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Receive failed: $e')),
      );
    }
  }

  Future<void> _rejectTaskFromChat(int taskId) async {
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
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),),
              ],),
              const SizedBox(height: 4),
              const Text(
                'Tell the assignee what needs to change so they can fix and resubmit.',
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
                    style:
                        TextStyle(color: Colors.white, fontWeight: FontWeight.w700),),
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
    if (reason == null || reason.isEmpty) return;
    try {
      await ref.read(tasksRepositoryProvider).reject(taskId, reason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task rejected — sent back to assignee')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reject failed: $e')),
      );
    }
  }

  Future<void> _replyClarificationFromChat(int taskId) async {
    final ctrl = TextEditingController();
    final answer = await showModalBottomSheet<String>(
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
                Icon(Icons.reply_all, color: AppColors.arenaBlue),
                SizedBox(width: 8),
                Text('Reply to clarification',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),),
              ],),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Type your answer…',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  final t = ctrl.text.trim();
                  if (t.isEmpty) return;
                  Navigator.pop(ctx, t);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.arenaBlue,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: const Text('Send reply',
                    style:
                        TextStyle(color: Colors.white, fontWeight: FontWeight.w700),),
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
    if (answer == null || answer.isEmpty) return;
    try {
      await ref
          .read(tasksRepositoryProvider)
          .replyClarification(taskId, answer);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reply sent')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reply failed: $e')),
      );
    }
  }

  Future<void> _rsvpMeeting(int meetingId, String rsvp) async {
    final repo = ref.read(chatRepositoryProvider);
    final label = switch (rsvp) {
      'accepted' => 'Accepted',
      'declined' => 'Declined',
      'tentative' => 'Maybe',
      _ => rsvp,
    };
    try {
      await repo.rsvpMeeting(meetingId, rsvp);
      if (!mounted) return;
      _showToast('RSVP recorded: $label');
      ref.invalidate(messagesControllerProvider(widget.groupId));
    } catch (e) {
      if (!mounted) return;
      final msg = switch (e) {
        ApiException(:final message) => message,
        _ => e.toString(),
      };
      _showToast('Failed: $msg', error: true);
    }
  }

  /// Called by the Composer when the user releases the mic — stores the
  /// recording as "pending preview" rather than uploading immediately.
  Future<void> _onVoiceRecorded(File file, Duration duration) async {
    setState(() => _pendingVoice = (file: file, duration: duration));
  }

  Future<void> _sendPendingVoice() async {
    final pending = _pendingVoice;
    if (pending == null) return;
    setState(() => _sendingVoice = true);
    final replyId = _replyingTo?.id;
    try {
      await ref
          .read(messagesControllerProvider(widget.groupId).notifier)
          .sendVoice(pending.file, duration: pending.duration, replyToId: replyId);
      if (!mounted) return;
      setState(() {
        _pendingVoice = null;
        _replyingTo = null;
        _sendingVoice = false;
      });
      _jumpToBottomNextFrame(force: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingVoice = false);
      final msg = switch (e) {
        ApiException(:final message) => message,
        _ => e.toString(),
      };
      _showToast('Failed to send voice: $msg', error: true);
    }
  }

  Future<void> _discardPendingVoice() async {
    final pending = _pendingVoice;
    if (pending == null) return;
    setState(() => _pendingVoice = null);
    pending.file.delete().catchError((_) => pending.file);
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messagesControllerProvider(widget.groupId));
    final currentUserId = ref.read(authControllerProvider).valueOrNull?.id;

    // ref.watch (not read) so the title rebuilds when groups finish loading
    // on cold start — otherwise the AppBar title stays empty.
    final groupsState = ref.watch(groupsControllerProvider).valueOrNull;
    final group = (groupsState ?? const [])
        .where((g) => g.id == widget.groupId)
        .firstOrNull;

    // Side-effect: scroll to bottom on first load / when new messages arrive.
    ref.listen<AsyncValue<List<MessageModel>>>(
      messagesControllerProvider(widget.groupId),
      (prev, next) {
        final list = next.valueOrNull;
        if (list == null) return;
        if (!_didInitialScroll) {
          _lastSeenLength = list.length;
          _didInitialScroll = true; // flip immediately so list becomes visible
          // Defer the scroll to after layout. The retry logic inside
          // _jumpToBottomNextFrame chases the bottom as the list grows
          // (so tall items like task cards don't get cut off).
          _jumpToBottomNextFrame(force: true);
          return;
        }
        if (list.length > _lastSeenLength) {
          final shouldJump = _isNearBottom();
          _lastSeenLength = list.length;
          if (shouldJump) _jumpToBottomNextFrame();
        }
      },
    );

    // Watch typing state for the WhatsApp-style indicator above the composer.
    final typing = ref.watch(typingControllerProvider(widget.groupId));

    return Scaffold(
      backgroundColor: AppColors.chatBg,
      // Resize when keyboard shows but DON'T let it shift the scroll anchor.
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        // Custom leading: unfocus FIRST so keyboard dismissal doesn't eat the
        // first tap, then pop. Default leading caused a "tap-twice to leave"
        // bug because Android first dismissed the keyboard, then the second
        // tap actually navigated.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () {
            FocusScope.of(context).unfocus();
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: InkWell(
          onTap: () => context.push('/chat/${widget.groupId}/info'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // For a 1-on-1 thread this is the OTHER person's name;
                      // for a group it's the group name. Empty while loading
                      // so we don't flash a placeholder.
                      group?.displayName ?? '',
                      textDirection: detectBidiDirection(group?.displayName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // Subtitle = the brand, but NOT for direct chats (their
                    // sentinel brand is just "Direct Messages").
                    if (group != null &&
                        !group.isDirect &&
                        (group.brand?.name.isNotEmpty ?? false))
                      Text(
                        group.brand!.name,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_canSeeTaskSummary())
            IconButton(
              icon: const Icon(Icons.dashboard_outlined),
              tooltip: 'Task summary',
              onPressed: () => GroupTaskSummarySheet.show(
                context,
                groupId: widget.groupId,
                groupTitle: group?.displayName ?? group?.brand?.name ?? 'Chat',
              ),
            ),
          IconButton(
            icon: const Icon(Icons.push_pin_outlined),
            tooltip: 'Pinned messages',
            onPressed: _showPinnedSheet,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Chat info',
            onPressed: () => context.push('/chat/${widget.groupId}/info'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => _buildError(e),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet — start the conversation!',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }
                // Show the list as soon as the data is available — the
                // _jumpToBottomNextFrame retry loop (kicked off in
                // ref.listen above) chases the bottom across a few frames
                // so any brief flash at the top is barely perceptible and
                // much less confusing than an empty screen.
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  itemBuilder: (ctx, i) {
                    final m = messages[i];
                    final isMine =
                        currentUserId != null && m.userId == currentUserId;

                    // System messages render as centered cards, not bubbles.
                    if (m.isSystemCard) {
                      // Sprint P.7 — did somebody already post a
                      // clarification_reply for this card's task? If yes
                      // we hide the Reply button so the creator can't
                      // double-answer.
                      bool alreadyAnswered = false;
                      if (m.type == MessageType.clarification) {
                        final tid = (m.payload?['task_id'] as num?)?.toInt()
                            ?? (m.payload?['primary_task_id'] as num?)
                                ?.toInt();
                        if (tid != null) {
                          for (final later in messages) {
                            if (later.id <= m.id) continue;
                            if (later.type !=
                                MessageType.clarificationReply) {
                              continue;
                            }
                            final lp = later.payload;
                            final lt = (lp?['task_id'] as num?)?.toInt()
                                ?? (lp?['primary_task_id'] as num?)?.toInt();
                            if (lt == tid) {
                              alreadyAnswered = true;
                              break;
                            }
                          }
                        }
                      }

                      // Hide receive / approve / reject once a LATER card for
                      // the same task has superseded it (no double-receive or
                      // double-approve).
                      bool alreadyReceived = false;
                      bool alreadyDecided = false;
                      if (m.type == MessageType.taskDone) {
                        final tid = (m.payload?['task_id'] as num?)?.toInt() ??
                            (m.payload?['primary_task_id'] as num?)?.toInt();
                        if (tid != null) {
                          for (final later in messages) {
                            if (later.id <= m.id) continue;
                            if (later.type != MessageType.taskDone) continue;
                            final lp = later.payload;
                            final lt = (lp?['task_id'] as num?)?.toInt() ??
                                (lp?['primary_task_id'] as num?)?.toInt();
                            if (lt != tid) continue;
                            final ev = lp?['event'] as String?;
                            if (ev == 'received' ||
                                ev == 'approved' ||
                                ev == 'rejected') {
                              alreadyReceived = true;
                            }
                            if (ev == 'approved' || ev == 'rejected') {
                              alreadyDecided = true;
                            }
                          }
                        }
                      }

                      return SystemCard(
                        message: m,
                        currentUserId: currentUserId,
                        // Show the client chip only inside custom rooms.
                        showBrand: group?.isCustom == true ||
                            group?.brand?.slug == 'custom-groups',
                        onOpenTask: (taskId) =>
                            context.push('/tasks/$taskId'),
                        onRsvpMeeting: (meetingId, rsvp) =>
                            _rsvpMeeting(meetingId, rsvp),
                        // Sprint P.1 — inline approve / reject / clarify-reply
                        // straight from the chat (no need to open task detail).
                        onApproveTask: (taskId) => _approveTaskFromChat(taskId),
                        onRejectTask: (taskId) => _rejectTaskFromChat(taskId),
                        // Sprint R — Receive gateway before approve/reject.
                        onReceiveTask: (taskId) => _receiveTaskFromChat(taskId),
                        onReplyClarification: (taskId) =>
                            _replyClarificationFromChat(taskId),
                        clarificationAnswered: alreadyAnswered,
                        alreadyReceived: alreadyReceived,
                        alreadyDecided: alreadyDecided,
                      );
                    }

                    final showSenderName = _shouldShowSenderName(messages, i);
                    final repliedTo = _findRepliedMessage(messages, m.replyToId);

                    return GestureDetector(
                      key: _keyFor(m.id),
                      onLongPress: () => _onLongPress(m, isMine),
                      child: MessageBubble(
                        message: m,
                        isMine: isMine,
                        showSenderName: showSenderName,
                        repliedTo: repliedTo,
                        myUserId: currentUserId ?? 0,
                        onToggleReaction: (emoji) => ref
                            .read(messagesControllerProvider(widget.groupId)
                                .notifier,)
                            .react(m.id, emoji),
                        onSenderTap: (isMine || m.sender == null)
                            ? null
                            : () => _showPersonActions(m),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // WhatsApp-style "X is typing..." bar above the composer.
          if (typing.hasAny) TypingIndicator(names: typing.names),
          if (_editingMessage != null && _pendingVoice == null)
            _EditingBanner(
              originalBody: _editingMessage!.body ?? '',
              onCancel: () => setState(() => _editingMessage = null),
            ),
          if (_replyingTo != null &&
              _pendingVoice == null &&
              _editingMessage == null)
            ReplyBanner(
              replyingTo: _replyingTo!,
              onCancel: () => setState(() => _replyingTo = null),
            ),
          if (_pendingVoice != null)
            VoicePreview(
              file: _pendingVoice!.file,
              duration: _pendingVoice!.duration,
              sending: _sendingVoice,
              onDelete: _discardPendingVoice,
              onSend: _sendPendingVoice,
            )
          else
            Composer(
              groupId: widget.groupId,
              focusNode: _composerFocus,
              onSendText: _sendText,
              // Hide attach + voice while editing — those are for new
              // messages only and would muddy the edit flow.
              onPickAttachment: _editingMessage == null
                  ? _pickAndSendAttachment
                  : null,
              onSendVoice:
                  _editingMessage == null ? _onVoiceRecorded : null,
              initialText: _editingMessage?.body,
              isEditing: _editingMessage != null,
            ),
        ],
      ),
    );
  }

  Widget _buildError(Object e) {
    final msg = e.toString().toLowerCase();
    final isConnIssue = msg.contains('connection') ||
        msg.contains('socket') ||
        msg.contains('timeout') ||
        msg.contains('could not');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isConnIssue ? Icons.wifi_off : Icons.error_outline,
              size: 56,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              isConnIssue
                  ? 'Could not connect to the server'
                  : 'Error loading messages',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              isConnIssue
                  ? 'Make sure the server is running'
                  : e.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref
                  .read(messagesControllerProvider(widget.groupId).notifier)
                  .refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  /// First message of a sender block shows the name; subsequent messages from
  /// the same sender within 5 minutes hide it.
  bool _shouldShowSenderName(List<MessageModel> messages, int index) {
    if (index == 0) return true;
    final current = messages[index];
    final prev = messages[index - 1];
    if (current.userId != prev.userId) return true;
    final currentTime = current.createdAt;
    final prevTime = prev.createdAt;
    if (currentTime == null || prevTime == null) return true;
    return currentTime.difference(prevTime).inMinutes >= 5;
  }

  /// O(n) lookup of the message we're replying to from the loaded page.
  /// Returns null if the parent isn't in the currently-loaded window
  /// (would require a separate fetch — Phase 2.5).
  MessageModel? _findRepliedMessage(List<MessageModel> messages, int? id) {
    if (id == null) return null;
    for (final m in messages) {
      if (m.id == id) return m;
    }
    return null;
  }
}

// Note: previous _TypingOrBrandSubtitle widget was removed — typing now
// renders as a WhatsApp-style TypingIndicator bar above the composer.

/// Sprint P.2 — slim banner above the composer that says "Editing message"
/// + a snippet of the original body + an ✕ to cancel. Mirrors the desktop
/// edit pill so the user has a clear escape hatch.
class _EditingBanner extends StatelessWidget {
  final String originalBody;
  final VoidCallback onCancel;

  const _EditingBanner({
    required this.originalBody,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.arenaBlue.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.arenaBlue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.edit, size: 16, color: AppColors.arenaBlue),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Editing message',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.arenaBlue,
                  ),
                ),
                Text(
                  originalBody,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.ink2,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.ink2,
            tooltip: 'Cancel edit',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}
