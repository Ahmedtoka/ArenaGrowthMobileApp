import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../data/leave_models.dart';
import '../data/leave_repository.dart';

final leaveRepositoryProvider = Provider<LeaveRepository>(
  (ref) => LeaveRepository(ref.watch(dioClientProvider)),
);

/// My requests + balance.
final myLeavesProvider = FutureProvider.autoDispose<MyLeaves>(
  (ref) => ref.read(leaveRepositoryProvider).mine(),
);

/// Requests awaiting my approval (managers only).
final pendingLeavesProvider =
    FutureProvider.autoDispose<List<LeaveRequestModel>>(
  (ref) => ref.read(leaveRepositoryProvider).pending(),
);
