import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/data/models/user_model.dart';
import '../controllers/typing_controller.dart';
import '../controllers/users_provider.dart';
import '../controllers/voice_recorder_controller.dart';

/// Picked user reference for an @mention.
class MentionPick {
  final int userId;
  final String name;
  const MentionPick({required this.userId, required this.name});
}

/// Chat composer: text field + send button + @mention autocomplete + attach.
///
/// Design notes:
///   - Uses [ValueListenableBuilder] on the controller so only the send
///     button rebuilds when the user types.
///   - When the cursor is inside an @<query> token, an autocomplete dropdown
///     appears above the composer with matching users from the group.
class Composer extends ConsumerStatefulWidget {
  /// Called when the user taps Send. Receives the text body and the list of
  /// mentioned user ids that survived in the final text.
  final Future<void> Function(String body, List<int> mentions) onSendText;

  /// Called when the user picks an attachment from the paperclip menu.
  /// May be null to hide the paperclip button.
  final Future<void> Function()? onPickAttachment;

  /// Called when a voice recording finishes — receives the file + duration.
  /// May be null to hide the mic button.
  final Future<void> Function(File file, Duration duration)? onSendVoice;

  /// The group context — needed to scope the mention autocomplete.
  final int groupId;

  /// Optional external focus node (used by the screen to re-focus after Reply).
  final FocusNode? focusNode;

  /// Sprint P.2 — text to prefill into the composer when entering edit mode.
  /// The parent flips this from null → body on Edit, and back to null on
  /// cancel/save. We detect the change in `didUpdateWidget` and reset the
  /// controller (focus is preserved).
  final String? initialText;

  /// True when the parent is in "editing" mode (banner above composer).
  /// The send button stays blue; pressing it calls [onSendText] which the
  /// parent rewires to perform a PATCH when this is true.
  final bool isEditing;

  const Composer({
    super.key,
    required this.onSendText,
    required this.groupId,
    this.onPickAttachment,
    this.onSendVoice,
    this.focusNode,
    this.initialText,
    this.isEditing = false,
  });

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  final _ctrl = TextEditingController();
  late final FocusNode _focus;
  bool _ownsFocus = false;
  bool _sending = false;

  /// User ids the user has already picked from autocomplete, indexed by the
  /// inserted name. We re-validate against current text on send (so deleted
  /// mentions are removed).
  final Map<String, int> _pickedMentions = {};

  /// The current @query the cursor is inside, or null. Drives the dropdown.
  String? _activeQuery;

  // Voice recording
  late final VoiceRecorder _recorder;
  bool _slideToCancelActive = false;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focus = widget.focusNode!;
    } else {
      _focus = FocusNode();
      _ownsFocus = true;
    }
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _ctrl.text = widget.initialText!;
      _ctrl.selection =
          TextSelection.collapsed(offset: _ctrl.text.length);
    }
    _ctrl.addListener(_onTextOrCursorChanged);
    _recorder = VoiceRecorder();
    _recorder.addListener(_onRecorderChanged);
  }

  @override
  void didUpdateWidget(covariant Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sprint P.2 — react to the parent entering / leaving edit mode.
    final entering = !oldWidget.isEditing && widget.isEditing;
    final leaving = oldWidget.isEditing && !widget.isEditing;
    if (entering) {
      final body = widget.initialText ?? '';
      _ctrl.value = TextEditingValue(
        text: body,
        selection: TextSelection.collapsed(offset: body.length),
      );
      _focus.requestFocus();
    } else if (leaving) {
      _ctrl.clear();
      _pickedMentions.clear();
    } else if (widget.isEditing &&
        widget.initialText != oldWidget.initialText &&
        widget.initialText != null) {
      // Different message being edited mid-session.
      _ctrl.value = TextEditingValue(
        text: widget.initialText!,
        selection:
            TextSelection.collapsed(offset: widget.initialText!.length),
      );
    }
  }

  void _onRecorderChanged() => setState(() {});

  @override
  void dispose() {
    _ctrl.removeListener(_onTextOrCursorChanged);
    _recorder.removeListener(_onRecorderChanged);
    _recorder.dispose();
    _ctrl.dispose();
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  // ── Voice recording ───────────────────────────────────────────
  Future<void> _startRecording() async {
    if (widget.onSendVoice == null) return;
    setState(() {
      _slideToCancelActive = true;
      _dragOffset = 0;
    });
    final ok = await _recorder.start();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission required'),
          backgroundColor: AppColors.arenaRed,
        ),
      );
      setState(() => _slideToCancelActive = false);
    }
  }

  Future<void> _stopAndSendRecording() async {
    final wasRecording = _recorder.state.isRecording;
    setState(() {
      _slideToCancelActive = false;
      _dragOffset = 0;
    });
    if (!wasRecording) return;
    final result = await _recorder.stop();
    if (result == null || widget.onSendVoice == null) return;
    try {
      await widget.onSendVoice!(result.file, result.duration);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send voice: $e'),
          backgroundColor: AppColors.arenaRed,
        ),
      );
    }
  }

  Future<void> _cancelRecording() async {
    setState(() {
      _slideToCancelActive = false;
      _dragOffset = 0;
    });
    await _recorder.cancel();
  }

  /// Scans backwards from the cursor for "@..." (no whitespace). Returns
  /// null if cursor isn't currently inside a mention query.
  void _onTextOrCursorChanged() {
    // Notify other clients that I'm typing — only AFTER the first 5 characters,
    // and the controller itself sends "started" at most once per window (then
    // auto-clears). So a whole message produces a single typing signal, never
    // a per-keystroke stream.
    if (_ctrl.text.trim().length >= 5) {
      ref.read(typingControllerProvider(widget.groupId).notifier).notifyTyping();
    }

    final sel = _ctrl.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      _setActiveQuery(null);
      return;
    }
    final text = _ctrl.text;
    final cursor = sel.baseOffset;
    if (cursor <= 0 || cursor > text.length) {
      _setActiveQuery(null);
      return;
    }
    // Walk back from cursor-1 looking for @ or whitespace.
    int? atIndex;
    for (int i = cursor - 1; i >= 0; i--) {
      final ch = text[i];
      if (ch == '@') {
        atIndex = i;
        break;
      }
      if (ch == ' ' || ch == '\n' || ch == '\t') {
        break;
      }
    }
    if (atIndex == null) {
      _setActiveQuery(null);
      return;
    }
    // @ must be at start-of-text OR preceded by whitespace.
    if (atIndex > 0) {
      final prev = text[atIndex - 1];
      if (prev != ' ' && prev != '\n' && prev != '\t') {
        _setActiveQuery(null);
        return;
      }
    }
    final query = text.substring(atIndex + 1, cursor);
    _setActiveQuery(query);
  }

  void _setActiveQuery(String? q) {
    if (_activeQuery == q) return;
    setState(() => _activeQuery = q);
  }

  /// Replace the current @<query> with @<picked.name> + space.
  void _insertMention(MentionPick picked) {
    final sel = _ctrl.selection;
    if (!sel.isValid) return;
    final text = _ctrl.text;
    final cursor = sel.baseOffset;
    // Find the @ position
    int? atIndex;
    for (int i = cursor - 1; i >= 0; i--) {
      final ch = text[i];
      if (ch == '@') {
        atIndex = i;
        break;
      }
      if (ch == ' ' || ch == '\n' || ch == '\t') break;
    }
    if (atIndex == null) return;

    final mention = '@${picked.name}';
    final newText =
        '${text.substring(0, atIndex)}$mention ${text.substring(cursor)}';
    final newCursor = atIndex + mention.length + 1;

    // userId < 0 is the special "@All" option — insert the text but don't
    // record it as an individual mention id.
    if (picked.userId > 0) {
      _pickedMentions['@${picked.name}'] = picked.userId;
    }
    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }

  /// Walks the final text to collect user_ids whose @name token is still there.
  List<int> _surveyMentions() {
    final text = _ctrl.text;
    final result = <int>[];
    final seen = <int>{};
    for (final entry in _pickedMentions.entries) {
      if (text.contains(entry.key) && seen.add(entry.value)) {
        result.add(entry.value);
      }
    }
    return result;
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final mentions = _surveyMentions();
    setState(() => _sending = true);
    try {
      await widget.onSendText(text, mentions);
      if (!mounted) return;
      _ctrl.clear();
      _pickedMentions.clear();
      // Tell others I stopped typing now that I sent.
      ref.read(typingControllerProvider(widget.groupId).notifier).notifyStopped();
      _focus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send: $e'),
          backgroundColor: AppColors.arenaRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = _recorder.state.isRecording;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_activeQuery != null && !isRecording)
          _MentionDropdown(
            groupId: widget.groupId,
            query: _activeQuery!,
            onPick: _insertMention,
          ),
        SafeArea(
          top: false,
          child: Container(
            color: AppColors.appBg,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (widget.onPickAttachment != null && !isRecording)
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    color: AppColors.ink2,
                    onPressed: _sending ? null : widget.onPickAttachment,
                    tooltip: 'Attach',
                  ),
                Expanded(
                  child: isRecording
                      ? _RecordingPill(
                          duration: _recorder.state.duration,
                          dragOffset: _dragOffset,
                        )
                      : Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      maxLines: 5,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        // Short hint → always fits on ONE line (the old
                        // two-line hint stretched the box and looked off).
                        hintText: 'Message',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                        hintStyle: TextStyle(color: AppColors.ink3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _ctrl,
                  builder: (context, value, _) {
                    final hasText = value.text.trim().isNotEmpty;
                    if (hasText || widget.onSendVoice == null) {
                      // Text → send button
                      return Material(
                        color: AppColors.arenaBlue,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: hasText && !_sending ? _send : null,
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: _sending
                                ? const Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        valueColor: AlwaysStoppedAnimation(
                                            Colors.white,),
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.send_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                          ),
                        ),
                      );
                    }
                    // Empty → hold-to-record mic
                    return GestureDetector(
                      onLongPressStart: (_) => _startRecording(),
                      onLongPressEnd: (_) {
                        if (_dragOffset < -80) {
                          _cancelRecording();
                        } else {
                          _stopAndSendRecording();
                        }
                      },
                      onLongPressMoveUpdate: (details) {
                        setState(() {
                          _dragOffset = details.offsetFromOrigin.dx;
                        });
                      },
                      child: Material(
                        color: _recorder.state.isRecording
                            ? AppColors.arenaRed
                            : AppColors.arenaBlue,
                        shape: const CircleBorder(),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            _recorder.state.isRecording
                                ? Icons.mic
                                : Icons.mic_none,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Floating panel above the composer with matching users for the current @query.
class _MentionDropdown extends ConsumerWidget {
  final int groupId;
  final String query;
  final void Function(MentionPick picked) onPick;

  const _MentionDropdown({
    required this.groupId,
    required this.query,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (groupId: groupId, query: query);
    final usersAsync = ref.watch(mentionableUsersProvider(args));

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: AppColors.divider),
          bottom: BorderSide(color: AppColors.divider),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      // Transparent Material ancestor so ListTiles render correctly inside
      // this coloured panel (Flutter 3.44 asserts otherwise).
      child: Material(
        type: MaterialType.transparency,
        child: usersAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Could not load members',
            style: TextStyle(color: Colors.red.shade400, fontSize: 13),
          ),
        ),
        data: (users) {
          final q = query.toLowerCase();
          final showAll = q.isEmpty || 'all'.startsWith(q);
          if (users.isEmpty && !showAll) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'No matching members',
                style: TextStyle(color: AppColors.ink3, fontSize: 13),
              ),
            );
          }
          return ListView(
            shrinkWrap: true,
            children: [
              // "@All" — first option, mentions the whole group.
              if (showAll)
                ListTile(
                  dense: true,
                  leading: const CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.arenaBlue,
                    child: Icon(Icons.groups, size: 18, color: Colors.white),
                  ),
                  title: const Text('All',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600,),),
                  subtitle: const Text('Mention the whole group',
                      style: TextStyle(fontSize: 11.5, color: AppColors.ink3),),
                  onTap: () =>
                      onPick(const MentionPick(userId: -1, name: 'All')),
                ),
              for (final u in users)
                _UserRow(
                  user: u,
                  onTap: () =>
                      onPick(MentionPick(userId: u.id, name: u.name)),
                ),
            ],
          );
        },
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;
  const _UserRow({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _parseHexColor(user.avatarColor) ?? AppColors.arenaBlue;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color,
              child: Text(
                user.initials ?? user.name.characters.first.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  if (user.jobTitle != null && user.jobTitle!.isNotEmpty)
                    Text(
                      [user.jobTitle, user.department]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.ink3,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final value = int.tryParse(h, radix: 16);
    if (value == null) return null;
    return Color(value);
  }
}

/// In-place "recording in progress" pill: pulsing red dot + duration +
/// slide-to-cancel hint.
class _RecordingPill extends StatelessWidget {
  final Duration duration;
  final double dragOffset;

  const _RecordingPill({required this.duration, required this.dragOffset});

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final willCancel = dragOffset < -80;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: AppColors.arenaRed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _fmt(duration),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  willCancel ? Icons.delete : Icons.chevron_left,
                  size: 18,
                  color: willCancel ? AppColors.arenaRed : AppColors.ink3,
                ),
                const SizedBox(width: 4),
                Text(
                  willCancel ? 'Release to cancel' : 'Slide to cancel',
                  style: TextStyle(
                    fontSize: 13,
                    color: willCancel ? AppColors.arenaRed : AppColors.ink3,
                    fontWeight:
                        willCancel ? FontWeight.w600 : FontWeight.w400,
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
