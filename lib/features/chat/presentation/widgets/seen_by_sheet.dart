import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/text_direction_util.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/models/message_model.dart';
import '../controllers/chat_providers.dart';

/// Bottom sheet listing WHO has seen a message (and, for voice notes, who
/// played it) + WHEN. Reused from both the seen-indicator tap and the
/// long-press "Seen by" action.
class SeenBySheet {
  static Future<void> show(
      BuildContext context, WidgetRef ref, MessageModel message,) {
    final isVoice = message.type == MessageType.voice;
    final repo = ref.read(chatRepositoryProvider);
    final future = Future.wait([
      repo.messageSeenBy(message.id),
      isVoice
          ? repo.messagePlayedBy(message.id)
          : Future<List<Map<String, dynamic>>>.value(const []),
    ]);

    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: FutureBuilder<List<List<Map<String, dynamic>>>>(
          future: future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final seen = snap.data?[0] ?? const [];
            final played = snap.data?.elementAtOrNull(1) ?? const [];
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: AppColors.ink3.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  _section(
                    icon: Icons.done_all,
                    iconColor: const Color(0xFF2235FF),
                    title:
                        seen.isEmpty ? 'Not seen yet' : 'Seen by ${seen.length}',
                    people: seen,
                    timeKey: 'seen_at',
                    emptyText: 'No one has opened this yet.',
                  ),
                  if (isVoice) ...[
                    const Divider(height: 1),
                    _section(
                      icon: Icons.headphones,
                      iconColor: const Color(0xFF10B981),
                      title: played.isEmpty
                          ? 'Not played yet'
                          : 'Played by ${played.length}',
                      people: played,
                      timeKey: 'played_at',
                      emptyText: 'Seen, but nobody has listened yet.',
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static Widget _section({
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<Map<String, dynamic>> people,
    required String timeKey,
    required String emptyText,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,),),
            ],
          ),
        ),
        if (people.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(emptyText,
                style: const TextStyle(fontSize: 13, color: AppColors.ink3),),
          )
        else
          for (final r in people)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: UserAvatar(
                name: (r['name'] ?? '') as String,
                avatarUrl: r['avatar_url'] as String?,
                size: 30,
              ),
              title: Text((r['name'] ?? 'Someone') as String,
                  textDirection: detectBidiDirection((r['name'] ?? '') as String),
                  style: const TextStyle(fontSize: 14),),
              trailing: Text(
                _label(r[timeKey] as String?),
                style: const TextStyle(fontSize: 11, color: AppColors.ink3),
              ),
            ),
      ],
    );
  }

  static String _label(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return DateFormat('d MMM, h:mm a').format(dt);
  }
}
