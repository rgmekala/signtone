import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import 'auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  int _tab = 0;
  late final AuthService _authService;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authService = context.read<AuthService>();
      _authService.addListener(_onAuthChanged);
    });
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (_authService.isAuthenticated) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppConstants.routeHome, (_) => false,
      );
    }
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChanged);
    _pulseController.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      // Resize when keyboard appears to avoid overflow
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(  // ← fixes overflow
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  _HeroSection(pulseAnimation: _pulseAnimation),
                  const Spacer(),
                  _BottomSheet(
                    tab: _tab,
                    onTabChange: (t) => setState(() => _tab = t),
                    onError: _showError,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  final Animation<double> pulseAnimation;
  const _HeroSection({required this.pulseAnimation});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ScaleTransition(
          scale: pulseAnimation,
          child: Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(38),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.graphic_eq_rounded,
                size: 56, color: Colors.white),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(AppConstants.appName,
            style: AppTextStyles.displayLarge
                .copyWith(color: Colors.white, letterSpacing: 3)),
        const SizedBox(height: AppSpacing.xs),
        Text(AppConstants.appTagline, style: AppTextStyles.tagline),
      ],
    );
  }
}

class _BottomSheet extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onTabChange;
  final ValueChanged<String> onError;
  const _BottomSheet({
    required this.tab, required this.onTabChange, required this.onError,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _TabToggle(selected: tab, onTap: onTabChange),
          const SizedBox(height: AppSpacing.lg),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: tab == 0
                ? _GuestForm(key: const ValueKey('guest'), onError: onError)
                : _SocialOptions(key: const ValueKey('social'), onError: onError),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Your data is stored only on this device.\nWe never sell or share your information.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _TabToggle extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onTap;
  const _TabToggle({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        children: [
          _TabItem(label: 'Quick Join', index: 0, selected: selected, onTap: onTap),
          _TabItem(label: 'Sign In',    index: 1, selected: selected, onTap: onTap),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final String label;
  final int index, selected;
  final ValueChanged<int> onTap;
  const _TabItem({
    required this.label, required this.index,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = index == selected;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Center(
            child: Text(label,
                style: AppTextStyles.label.copyWith(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                )),
          ),
        ),
      ),
    );
  }
}

class _GuestForm extends StatefulWidget {
  final ValueChanged<String> onError;
  const _GuestForm({super.key, required this.onError});

  @override
  State<_GuestForm> createState() => _GuestFormState();
}

class _GuestFormState extends State<_GuestForm> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _isLoading  = false;

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final success = await context.read<AuthService>().loginAsGuest(
      displayName: _nameCtrl.text,
      email:       _emailCtrl.text,
      phone:       _phoneCtrl.text.isEmpty ? null : _phoneCtrl.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (!success) {
      widget.onError(
          context.read<AuthService>().errorMessage ?? 'Something went wrong.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _Field(
            ctrl: _nameCtrl, label: 'Display name',
            hint: 'How should we call you?',
            icon: Icons.person_outline_rounded,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Name is required' : null,
          ),
          _Field(
            ctrl: _emailCtrl, label: 'Email',
            hint: 'your@email.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          _Field(
            ctrl: _phoneCtrl, label: 'Phone (optional)',
            hint: '+1 555 000 0000',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: AppSpacing.sm),
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Join Now'),
          ),
        ],
      ),
    );
  }
}

class _SocialOptions extends StatefulWidget {
  final ValueChanged<String> onError;
  const _SocialOptions({super.key, required this.onError});

  @override
  State<_SocialOptions> createState() => _SocialOptionsState();
}

class _SocialOptionsState extends State<_SocialOptions> {
  bool _googleLoading   = false;
  bool _linkedInLoading = false;

  Future<void> _googleSignIn() async {
    setState(() => _googleLoading = true);
    final success = await context.read<AuthService>().loginWithGoogle();
    if (!mounted) return;
    setState(() => _googleLoading = false);
    if (!success) {
      final msg = context.read<AuthService>().errorMessage;
      if (msg != null) widget.onError(msg);
    }
  }

  Future<void> _linkedInSignIn() async {
    setState(() => _linkedInLoading = true);
    final success = await context.read<AuthService>().loginWithLinkedIn();
    if (!mounted) return;
    setState(() => _linkedInLoading = false);
    if (!success) {
      final msg = context.read<AuthService>().errorMessage;
      if (msg != null) widget.onError(msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SocialButton(
          isLoading: _googleLoading, onTap: _googleSignIn,
          logo: _GoogleLogo(), label: 'Continue with Google',
          borderColor: const Color(0xFFDDDDDD),
          textColor: AppColors.textPrimary, bgColor: Colors.white,
        ),
        const SizedBox(height: AppSpacing.md),
        _SocialButton(
          isLoading: _linkedInLoading, onTap: _linkedInSignIn,
          logo: _LinkedInLogo(), label: 'Continue with LinkedIn',
          borderColor: const Color(0xFF0A66C2),
          textColor: const Color(0xFF0A66C2), bgColor: Colors.white,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text('LinkedIn required for conferences',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textHint)),
            ),
            const Expanded(child: Divider()),
          ],
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;
  final Widget logo;
  final String label;
  final Color borderColor, textColor, bgColor;
  const _SocialButton({
    required this.isLoading, required this.onTap, required this.logo,
    required this.label, required this.borderColor,
    required this.textColor, required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: borderColor),
          boxShadow: AppShadows.card,
        ),
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: textColor))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    logo,
                    const SizedBox(width: AppSpacing.sm),
                    Text(label,
                        style: AppTextStyles.button.copyWith(color: textColor)),
                  ],
                ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
        width: 24, height: 24,
        child: CustomPaint(painter: _GoogleLogoPainter()));
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width / 2;
    final sw = size.width * 0.18;
    void arc(double start, double sweep, Color color) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        start, sweep, false,
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = sw,
      );
    }
    arc(-1.4, 2.2, const Color(0xFF4285F4));
    arc(-2.8, 1.4, const Color(0xFFEA4335));
    arc( 2.2, 1.4, const Color(0xFFFBBC05));
    arc( 0.8, 1.4, const Color(0xFF34A853));
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - size.height * 0.12, r + 2, size.height * 0.24),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - size.height * 0.1, r - 2, size.height * 0.2),
      Paint()..color = const Color(0xFF4285F4),
    );
  }
  @override
  bool shouldRepaint(_) => false;
}

class _LinkedInLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24, height: 24,
      decoration: BoxDecoration(
        color: const Color(0xFF0A66C2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Center(
        child: Text('in',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final IconData icon;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  const _Field({
    required this.ctrl, required this.label, required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        validator: validator,
        style: AppTextStyles.body,
        decoration: InputDecoration(
          labelText: label, hintText: hint,
          prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
          filled: true, fillColor: AppColors.surfaceDark,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.error, width: 1.5),
          ),
        ),
      ),
    );
  }
}
