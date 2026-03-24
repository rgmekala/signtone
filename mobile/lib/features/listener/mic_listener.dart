import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../features/auth/auth_service.dart';
import 'listener_service.dart';

class MicListenerScreen extends StatefulWidget {
  const MicListenerScreen({super.key});

  @override
  State<MicListenerScreen> createState() => _MicListenerScreenState();
}

class _MicListenerScreenState extends State<MicListenerScreen>
    with TickerProviderStateMixin {

  // Cache the Provider reference - context.read is NOT safe in dispose()
  late final ListenerService _listener;

  late final AnimationController _ringController;
  late final List<Animation<double>> _ringAnimations;

  @override
  void initState() {
    super.initState();

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _ringAnimations = List.generate(3, (i) {
      final start = i * 0.25;
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _ringController,
          curve: Interval(start, (start + 0.75).clamp(0, 1),
              curve: Curves.easeOut),
        ),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Safe to call context.read here - cache the reference for use in dispose()
    _listener = context.read<ListenerService>();
    _listener.addListener(_onListenerStateChange);
  }

  void _onListenerStateChange() {
    if (!mounted) return;
    if (_listener.state == ListenerState.matched &&
        _listener.matchData != null) {
      Navigator.of(context).pushNamed(
        AppConstants.routeConfirm,
        arguments: _listener.matchData,
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ringController.dispose();
    // Safe - using cached reference, NOT context.read()
    _listener.removeListener(_onListenerStateChange);
    super.dispose();
  }

  Future<void> _toggleListener() async {
    if (_listener.isListening) {
      await _listener.stop();
    } else {
      await _listener.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(auth),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.lg),
            _StatusBanner(state: _listener.state),
            const Spacer(),
            _MicButton(
              state: _listener.state,
              ringAnimations: _ringAnimations,
              ringController: _ringController,
              onTap: _toggleListener,
            ),
            const Spacer(),
            _BottomHint(state: _listener.state),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
      bottomNavigationBar: _BottomNav(),
    );
  }

  AppBar _buildAppBar(AuthService auth) {
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.graphic_eq_rounded,
              color: AppColors.primary, size: 22),
          const SizedBox(width: AppSpacing.xs),
          Text(AppConstants.appName,
              style: AppTextStyles.headline
                  .copyWith(color: AppColors.primary)),
        ],
      ),
      actions: [
        GestureDetector(
          onTap: () =>
              Navigator.of(context).pushNamed(AppConstants.routeProfile),
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primaryLight,
              backgroundImage: auth.avatarUrl != null
                  ? NetworkImage(auth.avatarUrl!)
                  : null,
              child: auth.avatarUrl == null
                  ? Text(
                      auth.displayName.isNotEmpty
                          ? auth.displayName[0].toUpperCase()
                          : 'S',
                      style: AppTextStyles.label
                          .copyWith(color: Colors.white),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────
// Status Banner
// ─────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  final ListenerState state;
  const _StatusBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      ListenerState.idle =>
        ('Tap the mic to start listening', AppColors.textSecondary,
            Icons.mic_off_rounded),
      ListenerState.listening =>
        ('Listening for Signtone signals…', AppColors.primary,
            Icons.mic_rounded),
      ListenerState.detecting =>
        ('Signal detected - matching…', AppColors.warning,
            Icons.search_rounded),
      ListenerState.matched =>
        ('Match found!', AppColors.success, Icons.check_circle_rounded),
      ListenerState.error =>
        ('Microphone error - tap to retry', AppColors.error,
            Icons.error_outline_rounded),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(label,
              style: AppTextStyles.caption.copyWith(color: color)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// Mic Button with pulse rings
// ─────────────────────────────────────────
class _MicButton extends StatelessWidget {
  final ListenerState state;
  final List<Animation<double>> ringAnimations;
  final AnimationController ringController;
  final VoidCallback onTap;

  const _MicButton({
    required this.state,
    required this.ringAnimations,
    required this.ringController,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = state == ListenerState.listening ||
        state == ListenerState.detecting;

    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isActive)
            ...ringAnimations.map((anim) => AnimatedBuilder(
                  animation: anim,
                  builder: (_, __) => Transform.scale(
                    scale: 0.5 + anim.value * 0.5,
                    child: Opacity(
                      opacity: (1 - anim.value).clamp(0, 1),
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.listenerPulse,
                        ),
                      ),
                    ),
                  ),
                )),
          GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? AppColors.primary : AppColors.surfaceDark,
                boxShadow: isActive ? AppShadows.button : [],
              ),
              child: Icon(
                isActive ? Icons.mic_rounded : Icons.mic_none_rounded,
                size: 56,
                color: isActive ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// Bottom hint text
// ─────────────────────────────────────────
class _BottomHint extends StatelessWidget {
  final ListenerState state;
  const _BottomHint({required this.state});

  @override
  Widget build(BuildContext context) {
    final text = switch (state) {
      ListenerState.idle      => 'Works in background while the app is open',
      ListenerState.listening => 'Detecting ultrasonic signals in the room',
      ListenerState.detecting => 'Analysing frequencies…',
      ListenerState.matched   => 'Opening confirmation…',
      ListenerState.error     => 'Check microphone permissions in Settings',
    };

    return Text(
      text,
      style: AppTextStyles.caption,
      textAlign: TextAlign.center,
    );
  }
}

// ─────────────────────────────────────────
// Bottom Navigation
// ─────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)?.settings.name;

    return BottomNavigationBar(
      currentIndex: _indexForRoute(route),
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textHint,
      backgroundColor: AppColors.surface,
      elevation: 8,
      onTap: (i) => _onTap(context, i),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.mic_rounded),
          label: 'Listen',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.history_rounded),
          label: 'History',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_rounded),
          label: 'Profile',
        ),
      ],
    );
  }

  int _indexForRoute(String? route) {
    return switch (route) {
      AppConstants.routeHistory => 1,
      AppConstants.routeProfile || AppConstants.routeEditProfile => 2,
      _ => 0,
    };
  }

  void _onTap(BuildContext context, int i) {
    final routes = [
      AppConstants.routeHome,
      AppConstants.routeHistory,
      AppConstants.routeProfile,
    ];
    if (i < routes.length) {
      Navigator.of(context).pushReplacementNamed(routes[i]);
    }
  }
}
