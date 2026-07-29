import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// A tinted status label (e.g. Approved / Pending / Rejected). One consistent
/// look for every status chip in the app.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusPill(this.label, {super.key, required this.color, this.icon});

  /// Semantic shortcut — maps a status keyword to a colour.
  factory StatusPill.forStatus(String status) {
    final s = status.toLowerCase();
    final color = switch (s) {
      'approved' || 'done' || 'delivered' || 'completed' || 'active' =>
        AppColors.success,
      'rejected' || 'cancelled' || 'overdue' || 'late' => AppColors.arenaRed,
      'pending' || 'awaiting' || 'waiting' || 'in_progress' || 'review' =>
        AppColors.warning,
      _ => AppColors.arenaBlue,
    };
    return StatusPill(status.replaceAll('_', ' '), color: color);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            AppSpacing.hXs,
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}
