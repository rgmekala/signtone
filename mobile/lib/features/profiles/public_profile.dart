import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../features/auth/auth_service.dart';
import '../../shared/services/api_client.dart';

class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  final _api = ApiClient();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _isEditing = false;

  late TextEditingController _displayNameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _cityCtrl;
  late TextEditingController _countryCtrl;

  @override
  void initState() {
    super.initState();
    _displayNameCtrl = TextEditingController();
    _emailCtrl       = TextEditingController();
    _cityCtrl        = TextEditingController();
    _countryCtrl     = TextEditingController();
    _populateFields();
  }

  void _populateFields() {
    final user = context.read<AuthService>().user;
    if (user == null) return;
    // Public profile falls back to LinkedIn data if not explicitly set
    _displayNameCtrl.text =
        user['display_name'] as String? ?? user['name'] as String? ?? '';
    _emailCtrl.text =
        user['public_email'] as String? ?? user['email'] as String? ?? '';
    _cityCtrl.text    = user['city']    as String? ?? '';
    _countryCtrl.text = user['country'] as String? ?? '';
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _emailCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await _api.updatePublicProfile({
        'display_name': _displayNameCtrl.text.trim(),
        'public_email': _emailCtrl.text.trim(),
        'city':         _cityCtrl.text.trim(),
        'country':      _countryCtrl.text.trim(),
      });
      await context.read<AuthService>().refreshProfile();
      if (!mounted) return;
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Public profile updated.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Public Profile'),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => setState(() => _isEditing = true),
              tooltip: 'Edit',
            ),
          if (_isEditing)
            TextButton(
              onPressed: _isLoading ? null : _saveProfile,
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                          CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
        ],
      ),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                // Info banner explaining public profile
                _InfoBanner(),
                const SizedBox(height: AppSpacing.lg),

                _isEditing
                    ? _EditForm(
                        formKey:         _formKey,
                        displayNameCtrl: _displayNameCtrl,
                        emailCtrl:       _emailCtrl,
                        cityCtrl:        _cityCtrl,
                        countryCtrl:     _countryCtrl,
                      )
                    : _ViewForm(user: user),

                const SizedBox(height: AppSpacing.xl),
                _SwitchProfileButton(),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
      bottomNavigationBar: _BottomNav(),
    );
  }
}

// ─────────────────────────────────────────
// Info Banner
// ─────────────────────────────────────────
class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.accent.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Used for sweepstakes & broadcasts',
                    style: AppTextStyles.label
                        .copyWith(color: AppColors.accent)),
                const SizedBox(height: 2),
                Text(
                  'Only your display name and email are shared '
                  'when you register with your public profile. '
                  'No LinkedIn data is sent.',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// View Mode
// ─────────────────────────────────────────
class _ViewForm extends StatelessWidget {
  final Map<String, dynamic> user;
  const _ViewForm({required this.user});

  @override
  Widget build(BuildContext context) {
    final displayName =
        user['display_name'] as String? ?? user['name'] as String? ?? '-';
    final email =
        user['public_email'] as String? ?? user['email'] as String? ?? '-';
    final city    = user['city']    as String? ?? '';
    final country = user['country'] as String? ?? '';
    final location =
        [city, country].where((s) => s.isNotEmpty).join(', ');

    return Column(
      children: [
        // Preview card - shows exactly what organizers see
        _PreviewCard(
          displayName: displayName,
          email: email,
          location: location,
        ),
        const SizedBox(height: AppSpacing.lg),
        _InfoTile(
            icon: Icons.badge_rounded,
            label: 'Display name',
            value: displayName),
        _InfoTile(
            icon: Icons.email_rounded,
            label: 'Email',
            value: email),
        _InfoTile(
            icon: Icons.location_on_rounded,
            label: 'Location',
            value: location.isNotEmpty ? location : '-'),
      ],
    );
  }
}

// ─────────────────────────────────────────
// Organizer Preview Card
// ─────────────────────────────────────────
class _PreviewCard extends StatelessWidget {
  final String displayName, email, location;
  const _PreviewCard({
    required this.displayName,
    required this.email,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_rounded,
                  color: Colors.white70, size: 14),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'What organizers see',
                style: AppTextStyles.caption
                    .copyWith(color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(displayName,
              style: AppTextStyles.displaySmall
                  .copyWith(color: Colors.white)),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const Icon(Icons.email_rounded,
                  size: 14, color: Colors.white70),
              const SizedBox(width: AppSpacing.xs),
              Text(email,
                  style: AppTextStyles.caption
                      .copyWith(color: Colors.white70)),
            ],
          ),
          if (location.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                const Icon(Icons.location_on_rounded,
                    size: 14, color: Colors.white70),
                const SizedBox(width: AppSpacing.xs),
                Text(location,
                    style: AppTextStyles.caption
                        .copyWith(color: Colors.white70)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.caption),
                const SizedBox(height: 2),
                Text(value, style: AppTextStyles.body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// Edit Form
// ─────────────────────────────────────────
class _EditForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController displayNameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController cityCtrl;
  final TextEditingController countryCtrl;

  const _EditForm({
    required this.formKey,
    required this.displayNameCtrl,
    required this.emailCtrl,
    required this.cityCtrl,
    required this.countryCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        children: [
          _Field(
            ctrl: displayNameCtrl,
            label: 'Display name',
            hint: 'e.g. Alex M.',
            icon: Icons.badge_rounded,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          _Field(
            ctrl: emailCtrl,
            label: 'Email',
            hint: 'contact@example.com',
            icon: Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (!v.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          _Field(
            ctrl: cityCtrl,
            label: 'City',
            hint: 'San Francisco',
            icon: Icons.location_city_rounded,
          ),
          _Field(
            ctrl: countryCtrl,
            label: 'Country',
            hint: 'United States',
            icon: Icons.flag_rounded,
          ),
        ],
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
    required this.ctrl,
    required this.label,
    required this.hint,
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
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
          filled: true,
          fillColor: AppColors.surfaceDark,
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
            borderSide:
                const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide:
                const BorderSide(color: AppColors.error, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// Switch to Professional Profile
// ─────────────────────────────────────────
class _SwitchProfileButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context)
          .pushReplacementNamed(AppConstants.routeProfile),
      icon: const Icon(Icons.badge_rounded),
      label: const Text('Edit Professional Profile'),
    );
  }
}

// ─────────────────────────────────────────
// Bottom Nav (shared)
// ─────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 2,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textHint,
      backgroundColor: AppColors.surface,
      elevation: 8,
      onTap: (i) {
        final routes = [
          AppConstants.routeHome,
          AppConstants.routeHistory,
          AppConstants.routeProfile,
        ];
        Navigator.of(context).pushReplacementNamed(routes[i]);
      },
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.mic_rounded), label: 'Listen'),
        BottomNavigationBarItem(
            icon: Icon(Icons.history_rounded), label: 'History'),
        BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded), label: 'Profile'),
      ],
    );
  }
}
