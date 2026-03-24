import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'constants.dart';
import '../features/auth/auth_service.dart';
import '../features/auth/login_screen.dart';
import '../features/listener/mic_listener.dart';
import '../features/confirmation/confirm_card.dart';
import '../features/history/activity_log.dart';
import '../features/profiles/professional_profile.dart';
import '../features/profiles/public_profile.dart';

class AppRouter {
  AppRouter._();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppConstants.routeSplash:
        return _fade(const _SplashGate());

      case AppConstants.routeLogin:
        return _fade(const LoginScreen());

      case AppConstants.routeHome:
        // ✅ NO _AuthGuard here - listener is open to everyone
        return _fade(const MicListenerScreen());

      case AppConstants.routeConfirm:
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        // ✅ Confirm still needs auth - user will have JWT by the time they get here
        return _slide(
          _AuthGuard(child: ConfirmCard(matchData: args)),
          direction: _SlideDirection.up,
        );

      case AppConstants.routeHistory:
        return _slide(
          const _AuthGuard(child: ActivityLogScreen()),
        );

      case AppConstants.routeProfile:
        return _slide(
          const _AuthGuard(child: ProfessionalProfileScreen()),
        );

      case AppConstants.routeEditProfile:
        return _slide(
          const _AuthGuard(child: PublicProfileScreen()),
        );

      default:
        return _fade(const _NotFoundScreen());
    }
  }
}

// ─────────────────────────────────────────
// Auth Guard - wraps screens that require login
// (NOT used on routeHome anymore)
// ─────────────────────────────────────────
class _AuthGuard extends StatelessWidget {
  final Widget child;
  const _AuthGuard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        switch (auth.status) {
          case AuthStatus.unknown:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          case AuthStatus.unauthenticated:
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushNamedAndRemoveUntil(
                AppConstants.routeLogin,
                (_) => false,
              );
            });
            return const SizedBox.shrink();
          case AuthStatus.authenticated:
            return child;
        }
      },
    );
  }
}

// ─────────────────────────────────────────
// Splash Gate - always goes to Home (listener)
// Login is now optional / profile-driven
// ─────────────────────────────────────────
class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(
      const Duration(milliseconds: AppConstants.splashDurationMs),
    );
    if (!mounted) return;

    final auth = context.read<AuthService>();

    if (auth.status == AuthStatus.unknown) {
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 100));
        return auth.status == AuthStatus.unknown;
      });
    }

    if (!mounted) return;

    // ✅ Always go to listener - auth is no longer a gate
    Navigator.of(context).pushReplacementNamed(AppConstants.routeHome);
  }

  @override
  Widget build(BuildContext context) => const _SplashScreen();
}

// ─────────────────────────────────────────
// Splash Screen UI (unchanged)
// ─────────────────────────────────────────
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF6C63FF),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.graphic_eq_rounded, size: 80, color: Colors.white),
            SizedBox(height: 24),
            Text(
              'Signtone',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Hear it. Sign it. Done.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// 404 Screen (unchanged)
// ─────────────────────────────────────────
class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Page not found'),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context)
                  .pushReplacementNamed(AppConstants.routeHome),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// Transition helpers (unchanged)
// ─────────────────────────────────────────
enum _SlideDirection { left, up }

PageRouteBuilder<T> _fade<T>(Widget page) => PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 300),
    );

PageRouteBuilder<T> _slide<T>(
  Widget page, {
  _SlideDirection direction = _SlideDirection.left,
}) {
  final begin = direction == _SlideDirection.up
      ? const Offset(0, 1)
      : const Offset(1, 0);

  return PageRouteBuilder(
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) => SlideTransition(
      position: Tween(begin: begin, end: Offset.zero).animate(
        CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
      ),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 350),
  );
}
