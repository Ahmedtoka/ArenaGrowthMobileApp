import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'authed_network_image.dart';

/// Single source of truth for "show a user's avatar in a circle".
///
/// If [avatarUrl] is set, fetches the image through [AuthedNetworkImage]
/// (which attaches the Sanctum bearer token, so private avatars work).
/// Otherwise falls back to colored initials computed from [name].
///
/// Drop this widget anywhere a user appears — chat bubble, task assignee
/// chip, member list, mention picker, etc. — instead of building a fresh
/// CircleAvatar each time.
class UserAvatar extends StatelessWidget {
  /// Display name. Used for initials fallback + deterministic colour.
  final String name;

  /// Authed avatar URL from `user.avatar_url`. Null → initials.
  final String? avatarUrl;

  /// Diameter in logical pixels. The default (32) matches the chat bubble.
  final double size;

  /// Optional override for the initials background. If null we hash [name].
  final Color? backgroundColor;

  const UserAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.size = 32,
    this.backgroundColor,
  });

  static const _hues = <Color>[
    AppColors.arenaBlue,
    Color(0xFFEC4899),
    Color(0xFF10B981),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFF06B6D4),
    AppColors.arenaRed,
  ];

  Color get _resolvedBackground {
    if (backgroundColor != null) return backgroundColor!;
    final hash = name.codeUnits.fold<int>(0, (a, c) => a + c);
    return _hues[hash.abs() % _hues.length];
  }

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;
    final fontSize = size * 0.42;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _resolvedBackground,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: hasAvatar
          ? AuthedNetworkImage(
              url: avatarUrl!,
              fit: BoxFit.cover,
              width: size,
              height: size,
            )
          : Text(
              _initials,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
    );
  }
}
