import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// A consistent section title with an optional count badge + trailing action.
/// Replaces the many one-off `Padding(child: Row(Text(...)))` headers.
class SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  final int? count;
  final Widget? trailing;

  const SectionHeader(
    this.title, {
    super.key,
    this.color = AppColors.ink2,
    this.count,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs, AppSpacing.md, AppSpacing.xs, AppSpacing.sm,),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w800, color: color,),
          ),
          if (count != null && count! > 0) ...[
            AppSpacing.hSm,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: AppRadius.rPill,
              ),
              child: Text('$count',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800, color: color,),),
            ),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
