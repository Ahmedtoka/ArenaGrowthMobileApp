import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/routes.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';

/// Full-screen branded splash shown on cold start. The native (OS) splash on
/// Android 12+ can only show a centered icon on a solid colour, so we render
/// the full Splash.png here for a beat, then route to home or login once the
/// auth bootstrap has resolved.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _proceed());
  }

  Future<void> _proceed() async {
    final start = DateTime.now();
    // Wait for the auth bootstrap (cached user → /auth/me refresh) to settle.
    try {
      await ref.read(authControllerProvider.future);
    } catch (_) {
      // Ignore — an auth error just means we route to login below.
    }
    // Keep the artwork on screen for a minimum beat so it doesn't flash.
    final elapsed = DateTime.now().difference(start);
    const minShow = Duration(milliseconds: 1600);
    if (elapsed < minShow) {
      await Future.delayed(minShow - elapsed);
    }
    if (!mounted) return;
    final loggedIn = ref.read(authControllerProvider).valueOrNull != null;
    context.go(loggedIn ? Routes.home : Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Image.asset(
          'assets/images/Splash.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
    );
  }
}
