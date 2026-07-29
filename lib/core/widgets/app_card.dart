import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// The one white card used everywhere — replaces ~130 inline
/// `Container(decoration: BoxDecoration(color: white, borderRadius: ...))`.
///
/// - Consistent radius ([AppRadius.md]) + padding ([AppSpacing.card]).
/// - Optional left [accent] stripe (brand/status colour).
/// - Optional [onTap] → ripple + pressed feedback.
class AppCard extends StatelessWidget {
  final Widget child;
  final Color? accent;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? background;
  final bool border;

  const AppCard({
    super.key,
    required this.child,
    this.accent,
    this.padding = AppSpacing.card,
    this.margin = const EdgeInsets.only(bottom: AppSpacing.sm),
    this.onTap,
    this.background,
    this.border = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = AppRadius.rMd;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? AppColors.surface,
        borderRadius: radius,
        border: accent != null
            ? Border(left: BorderSide(color: accent!, width: 3))
            : (border ? Border.all(color: AppColors.border) : null),
      ),
      child: child,
    );

    return Padding(
      padding: margin,
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: radius,
                onTap: onTap,
                child: content,
              ),
            ),
    );
  }
}
