import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../data/scorecard_repository.dart';

/// Plain providers (no codegen) — ships without a build_runner pass.
final scorecardRepositoryProvider = Provider<ScorecardRepository>((ref) {
  return ScorecardRepository(ref.watch(dioClientProvider));
});

/// Selected month as a (year, month) pair. Defaults to the current month.
final scorecardMonthProvider = StateProvider<(int, int)>((_) {
  final now = DateTime.now();
  return (now.year, now.month);
});

/// Pulls the authenticated employee's scorecard for the selected month.
final scorecardProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(scorecardRepositoryProvider);
  final (year, month) = ref.watch(scorecardMonthProvider);
  return repo.fetch(year: year, month: month);
});
