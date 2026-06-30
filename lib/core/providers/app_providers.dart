import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/dio_client.dart';
import '../services/attachment_downloader.dart';
import '../storage/secure_storage.dart';

part 'app_providers.g.dart';

/// Sprint Q — authenticated file downloader. Wraps Dio with the Sanctum
/// bearer token attached and adds share/open helpers on top.
///
/// Declared manually (not via @Riverpod) so we don't need to run
/// build_runner for this single provider — the generated app_providers.g.dart
/// only knows about the providers that existed at codegen time.
final attachmentDownloaderProvider = Provider<AttachmentDownloader>((ref) {
  final client = ref.watch(dioClientProvider);
  return AttachmentDownloader(client);
});

/// Initialized in `main()` and overridden into the ProviderScope.
@Riverpod(keepAlive: true)
SharedPreferences sharedPreferences(SharedPreferencesRef ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main() via ProviderScope.overrides',
  );
}

@Riverpod(keepAlive: true)
SecureStorage secureStorage(SecureStorageRef ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SecureStorage.withPrefs(prefs);
}

@Riverpod(keepAlive: true)
DioClient dioClient(DioClientRef ref) {
  final storage = ref.watch(secureStorageProvider);
  return DioClient(storage);
}

// Note: attachmentDownloaderProvider lives at the top of this file as a
// plain Provider — no @Riverpod annotation, so no codegen needed.

/// Device label used as the Sanctum token name on login (one token per device).
///
/// Phase 1: hardcoded string. Phase 2 will swap to `device_info_plus` once
/// the older pre-jni version is wired in (avoiding the forced NDK download).
@Riverpod(keepAlive: true)
Future<String> deviceName(DeviceNameRef ref) async {
  return 'Android Emulator · Arena OS';
}
