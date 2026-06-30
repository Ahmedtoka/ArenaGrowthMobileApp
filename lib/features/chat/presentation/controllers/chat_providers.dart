import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/realtime/reverb_client.dart';
import '../../data/repositories/chat_repository.dart';

part 'chat_providers.g.dart';

@Riverpod(keepAlive: true)
ChatRepository chatRepository(ChatRepositoryRef ref) {
  final client = ref.watch(dioClientProvider);
  return ChatRepository(client);
}

/// Shared ReverbClient instance. Disposes on app teardown.
@Riverpod(keepAlive: true)
ReverbClient reverbClient(ReverbClientRef ref) {
  final storage = ref.watch(secureStorageProvider);
  final client = ReverbClient(storage);
  ref.onDispose(client.dispose);
  return client;
}
