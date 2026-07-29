import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/utils/text_direction_util.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/status_pill.dart';
import '../controllers/action_center_providers.dart';

/// The notification center, rebuilt into four clean categories:
///   @ Mentions on me · ❓ Clarifications I owe · ✅ My tasks done · 🔄 Task updates
///
/// The first three are ACTION-required (you must reply / review) — their status
/// dot pulses until you open them. Task updates are informational.
///
/// Each row remembers, locally, whether you've opened it: opened rows dim and
/// the per-section counter (unread only) drops — so a notification you've acted
/// on stops shouting at you.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  static const _prefsKey = 'inbox_read_keys';

  /// Locally-remembered "I opened this" keys ("$category:$id").
  Set<String> _read = {};

  @override
  void initState() {
    super.initState();
    // Load the per-item read set.
    final prefs = ref.read(sharedPreferencesProvider);
    _read = (prefs.getStringList(_prefsKey) ?? const []).toSet();

    // Mark the whole inbox seen (clears the bell), then refresh the count.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await markActionCenterSeen(ref);
      if (mounted) ref.invalidate(actionCenterProvider);
    });
  }

  bool _isRead(String cat, ActionItem it) => _read.contains('$cat:${it.id}');

  Future<void> _open(String cat, ActionItem it, VoidCallback nav) async {
    final key = '$cat:${it.id}';
    if (!_read.contains(key)) {
      setState(() => _read = {..._read, key});
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setStringList(_prefsKey, _read.toList());
    }
    nav();
  }

  int _unread(String cat, List<ActionItem> items) =>
      items.where((it) => !_isRead(cat, it)).length;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(actionCenterProvider);
    return Scaffold(
      backgroundColor: AppColors.appBg,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(actionCenterProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AppErrorState(
          text: 'Couldn’t load your notifications.\nPull to retry.',
          onRetry: () => ref.invalidate(actionCenterProvider),
        ),
        data: (b) {
          final empty = b.mentions.isEmpty &&
              b.clarifications.isEmpty &&
              b.tasksDone.isEmpty &&
              b.updates.isEmpty;
          if (empty) {
            return const AppEmptyState(
              icon: Icons.notifications_none,
              text: 'You’re all caught up 🎉',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(actionCenterProvider),
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                _section(
                  cat: 'mentions',
                  title: '@ Mentions',
                  color: const Color(0xFFEF4444),
                  items: b.mentions,
                  actionRequired: true,
                  onTap: (it) {
                    if (it.groupId != null) context.push('/chat/${it.groupId}');
                  },
                ),
                _section(
                  cat: 'clarifications',
                  title: '❓ Clarifications you owe',
                  color: AppColors.warning,
                  items: b.clarifications,
                  actionRequired: true,
                  onTap: (it) => context.push('/tasks/${it.id}'),
                ),
                _section(
                  cat: 'tasks_done',
                  title: '✅ Tasks you assigned — done',
                  color: const Color(0xFF16A34A),
                  items: b.tasksDone,
                  actionRequired: true,
                  onTap: (it) => context.push('/tasks/${it.id}'),
                ),
                _section(
                  cat: 'updates',
                  title: '🔄 Task updates',
                  color: const Color(0xFF2563EB),
                  items: b.updates,
                  actionRequired: false,
                  onTap: (it) => context.push('/tasks/${it.id}'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _section({
    required String cat,
    required String title,
    required Color color,
    required List<ActionItem> items,
    required bool actionRequired,
    required void Function(ActionItem) onTap,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    final unread = _unread(cat, items);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Row(
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800, color: color,),),
              const SizedBox(width: 6),
              // Badge shows UNREAD only, so it drops as you open items.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                    color: unread > 0
                        ? color.withValues(alpha: 0.12)
                        : AppColors.ink3.withValues(alpha: 0.12),
                    borderRadius: AppRadius.rSm,),
                child: Text(unread > 0 ? '$unread' : 'all seen',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: unread > 0 ? color : AppColors.ink3,),),
              ),
            ],
          ),
        ),
        ...items.map((it) => _row(cat, it, color, actionRequired, onTap)),
      ],
    );
  }

  Widget _row(String cat, ActionItem it, Color color, bool actionRequired,
      void Function(ActionItem) onTap,) {
    final read = _isRead(cat, it);
    // Read rows dim right down; action-required unread rows keep full contrast.
    final opacity = read ? 0.55 : 1.0;

    return Opacity(
      opacity: opacity,
      child: AppCard(
        onTap: () => _open(cat, it, () => onTap(it)),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        accent: read ? AppColors.ink3 : color,
        background: read ? const Color(0xFFF3F4F6) : Colors.white,
        child: Row(
          children: [
            // ── Status indicator ──────────────────────────────────────
            // Action-required + unread → pulsing dot ("do something").
            // Read → static check. Informational unread → static dot.
            _StatusDot(
              color: color,
              read: read,
              pulse: actionRequired && !read,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: detectBidiDirection(it.title),
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight:
                              read ? FontWeight.w600 : FontWeight.w700,
                          color: AppColors.ink,),),
                  const SizedBox(height: 2),
                  Text(it.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: detectBidiDirection(it.subtitle),
                      style:
                          const TextStyle(fontSize: 12, color: AppColors.ink3),),
                  // "Action needed" tag — only while it still needs you.
                  if (actionRequired && !read) ...[
                    const SizedBox(height: 6),
                    StatusPill('Action needed', color: color, icon: Icons.bolt),
                  ],
                ],
              ),
            ),
            AppSpacing.hSm,
            if (it.at != null)
              Text(DateFormat('MMM d').format(it.at!),
                  style: const TextStyle(fontSize: 11, color: AppColors.ink3),),
            AppSpacing.hXs,
            const Icon(Icons.chevron_right, size: 18, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }
}

/// A small status dot. When [pulse] is true it breathes (opacity + halo) to
/// signal "this one needs action"; when [read] it collapses to a muted check.
class _StatusDot extends StatefulWidget {
  final Color color;
  final bool read;
  final bool pulse;
  const _StatusDot({required this.color, required this.read, required this.pulse});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.pulse && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.read) {
      return const Icon(Icons.check_circle, size: 18, color: AppColors.ink3);
    }
    if (!widget.pulse) {
      // Informational unread → static filled dot.
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }
    // Action-required unread → pulsing dot with a soft halo.
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value; // 0..1
        return SizedBox(
          width: 18,
          height: 18,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 10 + 8 * t,
                  height: 10 + 8 * t,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.25 * (1 - t)),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
