import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Consistent empty state — a muted icon + message (+ optional action).
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: AppColors.ink3),
            AppSpacing.vMd,
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.ink3, fontSize: 14)),
            if (actionLabel != null && onAction != null) ...[
              AppSpacing.vMd,
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Consistent error state — a message + Retry.
class AppErrorState extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const AppErrorState({
    super.key,
    this.text = 'Something went wrong.\nPull to retry.',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) => AppEmptyState(
        icon: Icons.wifi_off_rounded,
        text: text,
        actionLabel: onRetry != null ? 'Retry' : null,
        onAction: onRetry,
      );
}
