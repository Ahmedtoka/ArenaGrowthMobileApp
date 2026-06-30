import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers/app_providers.dart';
import 'push_service.dart';

part 'push_providers.g.dart';

@Riverpod(keepAlive: true)
PushService pushService(PushServiceRef ref) {
  final client = ref.watch(dioClientProvider);
  return PushService(client);
}

/// Fire-and-forget helper to wire push at app startup.
/// Safe to call multiple times — PushService.init() is idempotent.
Future<void> bootstrapPush(PushService svc) async {
  try {
    await svc.init();
  } catch (e) {
    if (kDebugMode) debugPrint('[push] bootstrap failed: $e');
  }
}
