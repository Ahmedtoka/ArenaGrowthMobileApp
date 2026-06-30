import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/data/models/user_model.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/calendar/presentation/screens/calendar_screen.dart';
import '../../features/chat/presentation/screens/conversation_screen.dart';
import '../../features/chat/presentation/screens/create_group_screen.dart';
import '../../features/chat/presentation/screens/group_info_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/inbox/presentation/screens/inbox_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/social/presentation/screens/social_tally_screen.dart';
import '../../features/scorecard/presentation/scorecard_screen.dart';
import '../../features/tasks/presentation/screens/task_detail_screen.dart';
import 'routes.dart';

part 'app_router.g.dart';

/// Globally accessible router — set by [appRouterProvider] the first time
/// the GoRouter instance is built. Lets non-widget code (e.g. the FCM
/// notification tap handler) navigate without needing a BuildContext.
GoRouter? appNavigator;

/// Top-level navigator key — exported so [ErrorReporter] can show the
/// global error bottom-sheet from any zone without a BuildContext.
/// Declared OUTSIDE the @Riverpod block so the annotation stays directly
/// attached to the `appRouter` function (otherwise build_runner can't
/// regenerate app_router.g.dart).
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'arenaRoot');

@Riverpod(keepAlive: true)
GoRouter appRouter(AppRouterRef ref) {
  // Bumping this ValueNotifier triggers GoRouter to re-evaluate `redirect`.
  final refresh = ValueNotifier<int>(0);
  ref.listen<AsyncValue<UserModel?>>(authControllerProvider, (_, __) {
    refresh.value++;
  });
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.home,
    debugLogDiagnostics: true,
    refreshListenable: refresh,
    // Sprint P.5 — chat conversation auto-scroll on return.
    observers: [chatRouteObserver],
    redirect: (ctx, state) {
      final auth = ref.read(authControllerProvider);

      // Still bootstrapping with no cached value — let the current route render.
      if (auth.isLoading && !auth.hasValue) return null;

      final loggedIn = auth.value != null;
      final atLogin = state.matchedLocation == Routes.login;

      if (!loggedIn && !atLogin) return Routes.login;
      if (loggedIn && atLogin) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: '/chat/:groupId',
        builder: (ctx, state) {
          final groupId =
              int.parse(state.pathParameters['groupId']!);
          return ConversationScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: '/chat/:groupId/info',
        builder: (ctx, state) {
          final groupId =
              int.parse(state.pathParameters['groupId']!);
          return GroupInfoScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: '/tasks/:taskId',
        builder: (ctx, state) {
          final taskId = int.parse(state.pathParameters['taskId']!);
          return TaskDetailScreen(taskId: taskId);
        },
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/social',
        builder: (_, __) => const SocialTallyScreen(),
      ),
      GoRoute(
        path: '/scorecard',
        builder: (_, __) => const ScorecardScreen(),
      ),
      GoRoute(
        path: '/groups/new',
        builder: (_, __) => const CreateGroupScreen(),
      ),
      GoRoute(
        path: '/inbox',
        builder: (_, __) => const InboxScreen(),
      ),
      GoRoute(
        path: '/calendar',
        builder: (_, __) => const CalendarScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, __) => const ProfileScreen(),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      appBar: AppBar(title: const Text('Error')),
      body: Center(child: Text('Page not found:\n${state.uri}')),
    ),
  );

  // Expose for non-widget callers (push notification tap → deep-link).
  appNavigator = router;
  return router;
}
