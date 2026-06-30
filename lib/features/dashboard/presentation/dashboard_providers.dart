import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../data/dashboard_repository.dart';

/// Plain providers (no codegen) so the dashboard ships without a build_runner
/// pass.
final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(dioClientProvider));
});

/// Selected quick period: today | week | half_month | month | 30d.
/// Defaults to "today" per the product decision.
final dashboardPeriodProvider = StateProvider<String>((_) => 'today');

/// Optional custom range — when set it overrides [dashboardPeriodProvider].
final dashboardRangeProvider = StateProvider<DateTimeRange?>((_) => null);

/// Pulls the role-aware dashboard summary for the current period/range.
/// Reacts automatically whenever the period or custom range changes.
final dashboardSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(dashboardRepositoryProvider);
  final range = ref.watch(dashboardRangeProvider);
  if (range != null) {
    return repo.summary(from: range.start, to: range.end);
  }
  final period = ref.watch(dashboardPeriodProvider);
  return repo.summary(period: period);
});
