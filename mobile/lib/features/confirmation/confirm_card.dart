import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../features/auth/auth_service.dart';
import '../../features/matching/match_service.dart';
import '../../features/listener/listener_service.dart';

class ConfirmCard extends StatefulWidget {
  final Map<String, dynamic> matchData;
  const ConfirmCard({super.key, required this.matchData});

  @override
  State<ConfirmCard> createState() => _ConfirmCardState();
}

class _ConfirmCardState extends State<ConfirmCard>
    with SingleTickerProviderStateMixin {
  late final MatchResult _match;
  late MatchService _matcher; // not final - set in didChangeDependencies

  String _selectedProfile = AppConstants.profileTypePublic;
  bool _isRegistering     = false;
  bool _isRegistered      = false;

  late Timer _dismissTimer;
  int _secondsLeft = AppConstants.confirmationAutoDismissSec;

  late final AnimationController _successController;
  late final Animation<double> _successScale;

  @override
  void initState() {
    super.initState();
    _match = MatchResult.fromJson(widget.matchData);
    // NOTE: _matcher is set in didChangeDependencies via Provider

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successScale = CurvedAnimation(
      parent: _successController,
      curve: Curves.elasticOut,
    );

    _startDismissTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Use the shared Provider instance - has the saved JWT token
    _matcher = context.read<MatchService>();
  }

  void _startDismissTimer() {
    _dismissTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _dismiss();
      }
    });
  }

  void _dismiss() {
    if (!mounted) return;
    context.read<ListenerService>().resetAndResume();
    Navigator.of(context).pop();
  }

  Future<void> _register() async {
    _dismissTimer.cancel();
    setState(() => _isRegistering = true);

    final result = await _matcher.register(
      eventId:     _match.eventId,
      signalId:    _match.raw['beacon_payload'] as String? ?? _match.signalId,
      profileType: _selectedProfile,
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _isRegistering = false;
        _isRegistered  = true;
      });
      _successController.forward();
      Future.delayed(const Duration(seconds: 3), _dismiss);
    } else {
      setState(() => _isRegistering = false);

      // Friendly error messages
      String raw = result.errorMessage ?? 'Registration failed.';
      String msg;
      Color  color;

      if (raw.contains('already registered')) {
        msg   = 'You\'re already registered for this event!';
        color = AppColors.warning;
      } else if (raw.contains('LinkedIn profile required')) {
        msg   = 'This event requires LinkedIn. Please sign in with LinkedIn.';
        color = AppColors.error;
      } else if (raw.contains('not active')) {
        msg   = 'This event is no longer active.';
        color = AppColors.error;
      } else if (raw.contains('maximum registrations')) {
        msg   = 'This event is full - no more spots available.';
        color = AppColors.error;
      } else {
        msg   = raw;
        color = AppColors.error;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: color,
          duration: const Duration(seconds: 4),
        ),
      );
      _startDismissTimer();
    }
  }

  @override
  void dispose() {
    _dismissTimer.cancel();
    _successController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black54,
      body: GestureDetector(
        onTap: _isRegistered ? null : _dismiss,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: _isRegistered
                ? _SuccessCard(
                    match:       _match,
                    profileType: _selectedProfile,
                    scaleAnim:   _successScale,
                  )
                : _PendingCard(
                    match:           _match,
                    secondsLeft:     _secondsLeft,
                    selectedProfile: _selectedProfile,
                    isRegistering:   _isRegistering,
                    onProfileChange: (v) =>
                        setState(() => _selectedProfile = v!),
                    onConfirm:       _register,
                    onDismiss:       _dismiss,
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// Pending Card - profile select + confirm
// ─────────────────────────────────────────
class _PendingCard extends StatelessWidget {
  final MatchResult match;
  final int secondsLeft;
  final String selectedProfile;
  final bool isRegistering;
  final ValueChanged<String?> onProfileChange;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const _PendingCard({
    required this.match,
    required this.secondsLeft,
    required this.selectedProfile,
    required this.isRegistering,
    required this.onProfileChange,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.md,
        AppSpacing.lg, AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),
              _CountdownPill(secondsLeft: secondsLeft),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.graphic_eq_rounded,
                    size: 14, color: AppColors.accent),
                const SizedBox(width: AppSpacing.xs),
                Text('Signal detected',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.accent)),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          Text(match.eventName, style: AppTextStyles.displaySmall),

          const SizedBox(height: AppSpacing.xs),

          Row(
            children: [
              const Icon(Icons.business_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Text(match.organizerName, style: AppTextStyles.caption),
              const SizedBox(width: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(match.eventTypeLabel,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.primary)),
              ),
            ],
          ),

          if (match.eventDescription.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(match.eventDescription,
                style: AppTextStyles.bodySecondary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],

          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.md),

          Text('Register as', style: AppTextStyles.label),
          const SizedBox(height: AppSpacing.sm),

          _ProfileSelector(
            selected:  selectedProfile,
            user:      user,
            onChanged: onProfileChange,
          ),

          const SizedBox(height: AppSpacing.lg),

          ElevatedButton(
            onPressed: isRegistering ? null : onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
            ),
            child: isRegistering
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Confirm Registration'),
          ),

          const SizedBox(height: AppSpacing.sm),

          OutlinedButton(
            onPressed: onDismiss,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.divider),
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// Profile Selector
// ─────────────────────────────────────────
class _ProfileSelector extends StatelessWidget {
  final String selected;
  final Map<String, dynamic>? user;
  final ValueChanged<String?> onChanged;

  const _ProfileSelector({
    required this.selected,
    required this.user,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProfileTile(
          value:      AppConstants.profileTypeProfessional,
          groupValue: selected,
          title:      user?['name'] as String? ?? 'Professional Profile',
          subtitle:   user?['headline'] as String? ?? 'LinkedIn profile',
          icon:       Icons.badge_rounded,
          onChanged:  onChanged,
        ),
        const SizedBox(height: AppSpacing.sm),
        _ProfileTile(
          value:      AppConstants.profileTypePublic,
          groupValue: selected,
          title:      user?['display_name'] as String? ?? 'Public Profile',
          subtitle:   'First name + email only',
          icon:       Icons.person_rounded,
          onChanged:  onChanged,
        ),
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final String value, groupValue, title, subtitle;
  final IconData icon;
  final ValueChanged<String?> onChanged;

  const _ProfileTile({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.07)
              : AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary,
                size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.label),
                  Text(subtitle, style: AppTextStyles.caption),
                ],
              ),
            ),
            Radio<String>(
              value:    value,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: AppColors.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// Countdown Pill
// ─────────────────────────────────────────
class _CountdownPill extends StatelessWidget {
  final int secondsLeft;
  const _CountdownPill({required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    final urgent = secondsLeft <= 10;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: (urgent ? AppColors.error : AppColors.textSecondary)
            .withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        'Closes in ${secondsLeft}s',
        style: AppTextStyles.caption.copyWith(
          color: urgent ? AppColors.error : AppColors.textSecondary,
          fontWeight: urgent ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// Success Card
// ─────────────────────────────────────────
class _SuccessCard extends StatelessWidget {
  final MatchResult match;
  final String profileType;
  final Animation<double> scaleAnim;

  const _SuccessCard({
    required this.match,
    required this.profileType,
    required this.scaleAnim,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.xl,
        AppSpacing.lg, AppSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: scaleAnim,
            child: Container(
              width: 80, height: 80,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 44),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('You\'re registered!', style: AppTextStyles.displaySmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            match.eventName,
            style: AppTextStyles.body
                .copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Using your ${profileType == AppConstants.profileTypeProfessional ? 'professional' : 'public'} profile',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Closing in 3 seconds…',
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}
