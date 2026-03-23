import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import 'auth_service.dart';

class LinkedInAuthScreen extends StatefulWidget {
  const LinkedInAuthScreen({super.key});

  @override
  State<LinkedInAuthScreen> createState() => _LinkedInAuthScreenState();
}

class _LinkedInAuthScreenState extends State<LinkedInAuthScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() => _isLoading = true);

    final auth = context.read<AuthService>();
    final success = await auth.loginWithLinkedIn();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!success && auth.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage!),
          backgroundColor: AppColors.error,
        ),
      );
    }
    // On success, router.dart observes AuthStatus and navigates to /home
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: AppSpacing.xxl),

              // ── Hero section ──
              _HeroSection(pulseAnimation: _pulseAnimation),

              // ── Bottom section ──
              _BottomSection(
                isLoading: _isLoading,
                onLoginTap: _handleLogin,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// Hero Section
// ─────────────────────────────────────────
class _HeroSection extends StatelessWidget {
  final Animation<double> pulseAnimation;
  const _HeroSection({required this.pulseAnimation});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Pulsing icon
        ScaleTransition(
          scale: pulseAnimation,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              size: 64,
              color: Colors.white,
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // App name
        Text(
          AppConstants.appName,
          style: AppTextStyles.displayLarge.copyWith(
            color: Colors.white,
            letterSpacing: 3,
          ),
        ),

        const SizedBox(height: AppSpacing.sm),

        // Tagline
        Text(
          AppConstants.appTagline,
          style: AppTextStyles.tagline,
        ),

        const SizedBox(height: AppSpacing.xxl),

        // Feature pills
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          alignment: WrapAlignment.center,
          children: const [
            _FeaturePill(icon: Icons.mic_none_rounded,   label: 'Listen'),
            _FeaturePill(icon: Icons.bolt_rounded,        label: 'Detect'),
            _FeaturePill(icon: Icons.how_to_reg_rounded, label: 'Register'),
          ],
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: AppTextStyles.caption.copyWith(color: Colors.white)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// Bottom Section
// ─────────────────────────────────────────
class _BottomSection extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onLoginTap;
  const _BottomSection({required this.isLoading, required this.onLoginTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // LinkedIn sign-in button
        _LinkedInButton(isLoading: isLoading, onTap: onLoginTap),

        const SizedBox(height: AppSpacing.md),

        // Privacy note
        Text(
          'We only read your public LinkedIn profile.\nNo posts. No messages. Ever.',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(
            color: Colors.white.withOpacity(0.7),
          ),
        ),

        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _LinkedInButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;
  const _LinkedInButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.button,
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primary,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // LinkedIn "in" logo (drawn with text - no asset needed)
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A66C2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Center(
                        child: Text(
                          'in',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Continue with LinkedIn',
                      style: AppTextStyles.button.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
