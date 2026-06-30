import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/push/push_providers.dart';
import '../../../attendance/presentation/controllers/attendance_controller.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/models/user_model.dart';

part 'auth_controller.g.dart';

@Riverpod(keepAlive: true)
AuthRepository authRepository(AuthRepositoryRef ref) {
  final client = ref.watch(dioClientProvider);
  final storage = ref.watch(secureStorageProvider);
  return AuthRepository(client, storage);
}

/// Holds the currently authenticated user, or `null` when signed out.
///
/// `build()` is the bootstrap: read cached user, then refresh from `/auth/me`
/// in the background. Any 401 during refresh clears the token and bumps
/// state to `null`, which the router watches to redirect to /login.
@Riverpod(keepAlive: true)
class AuthController extends _$AuthController {
  @override
  Future<UserModel?> build() async {
    final repo = ref.read(authRepositoryProvider);

    if (!await repo.hasToken()) {
      return null;
    }

    final cached = await repo.getCachedUser();

    // Bootstrap push on app startup if a session is already restored.
    bootstrapPush(ref.read(pushServiceProvider));

    // Fire-and-forget server refresh — if it fails (e.g. 401), clear token.
    repo.me().then((fresh) {
      state = AsyncData(fresh);
    }).catchError((Object e) async {
      await repo.logout();
      state = const AsyncData(null);
    });

    return cached;
  }

  /// Sign in. Returns true on success, false on failure (and surfaces the
  /// error via [state]). Caller can `ref.listen` for AsyncError to show snacks.
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    final deviceName = await ref.read(deviceNameProvider.future);

    state = const AsyncLoading();
    try {
      final user = await repo.login(
        email: email,
        password: password,
        deviceName: deviceName,
      );
      // A different person may be signing in on this same device — drop any
      // keepAlive caches tied to the previous user so nothing leaks across
      // accounts (attendance check-in state was the worst offender).
      _resetUserScopedCaches();
      state = AsyncData(user);
      // Bootstrap push notifications in the background. Failures are
      // logged but never block the login flow.
      bootstrapPush(ref.read(pushServiceProvider));
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<void> logout() async {
    final repo = ref.read(authRepositoryProvider);
    state = const AsyncLoading();
    // Unregister the FCM token on the server first so this device stops
    // receiving pushes.
    try {
      await ref.read(pushServiceProvider).deleteToken();
    } catch (_) {/* best-effort */}
    await repo.logout();
    _resetUserScopedCaches();
    state = const AsyncData(null);
  }

  /// Invalidate keepAlive providers that cache the current user's data so a
  /// subsequent login (possibly a different person on the same phone) starts
  /// completely fresh and independent of the previous session.
  void _resetUserScopedCaches() {
    ref.invalidate(attendanceControllerProvider);
  }

  /// Force a re-read of /auth/me. Useful after profile edits.
  Future<void> refresh() async {
    final repo = ref.read(authRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(repo.me);
  }

  /// Patch the in-memory user without hitting the network — used after a
  /// successful avatar upload so widgets that read auth state (sidebar
  /// tile, @-mention picker, etc.) rebuild immediately.
  void setUser(UserModel user) {
    state = AsyncData(user);
  }
}
