import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:permission_handler/permission_handler.dart';
import 'features/auth/auth_service.dart';
import 'features/listener/listener_service.dart';
import 'features/matching/match_service.dart';

class SigntoneApp extends StatelessWidget {
  const SigntoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Auth - top of the tree, everything depends on it
        ChangeNotifierProvider<AuthService>(
          create: (_) => AuthService(),
        ),

        // Listener - mic state, shared between home screen and confirm card
        ChangeNotifierProvider<ListenerService>(
          create: (_) => ListenerService(),
        ),

        // Matcher - signal matching + registration
        ChangeNotifierProvider<MatchService>(
          create: (_) => MatchService(),
        ),
      ],
      child: const _AppView(),
    );
  }
}

// ─────────────────────────────────────────
// _AppView - reads auth state once providers
// are available, then builds MaterialApp
// ─────────────────────────────────────────
class _AppView extends StatefulWidget {
  const _AppView();

  @override
  State<_AppView> createState() => _AppViewState();
}

class _AppViewState extends State<_AppView> {
  @override
  void initState() {
    super.initState();
    // Kick off auth initialization after first frame so
    // context.read() has access to the provider tree
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthService>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: AppConstants.routeSplash,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
