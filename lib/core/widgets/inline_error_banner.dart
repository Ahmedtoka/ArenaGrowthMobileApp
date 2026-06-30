import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A clean, always-visible error banner for use INSIDE forms / bottom sheets,
/// where a SnackBar would be hidden behind the sheet. Use it for validation
/// and submit failures so the user always sees what went wrong.
class InlineErrorBanner extends StatelessWidget {
  final String message;
  const InlineErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.arenaRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.arenaRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.arenaRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.arenaRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
