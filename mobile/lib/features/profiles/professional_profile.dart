import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../features/auth/auth_service.dart';
import '../../shared/services/api_client.dart';

class ProfessionalProfileScreen extends StatefulWidget {
  const ProfessionalProfileScreen({super.key});

  @override
  State<ProfessionalProfileScreen> createState() =>
      _ProfessionalProfileScreenState();
}

class _ProfessionalProfileScreenState
    extends State<ProfessionalProfileScreen> {
  final _api = ApiClient();
  bool _isLoading = false;
  bool _isEditing = false;

  // Edit controllers
  late TextEditingController _headlineCtrl;
  late TextEditingController _summaryCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _websiteCtrl;

  @override
  void initState() {
    super.initState();
    _headlineCtrl = TextEditingController();
    _summaryCtrl  = TextEditingController();
    _phoneCtrl    = TextEditingController();
    _websiteCtrl  = TextEditingController();
    _populateFields();
  }

  void _populateFields() {
    final user = context.read<AuthService>().user;
    if (user == null) return;
    _headlineCtrl.text = user['headline'] as String? ?? '';
    _summaryCtrl.text  = user['summary']  as String? ?? '';
    _phoneCtrl.text    = user['phone']    as String? ?? '';
    _websiteCtrl.text  = user['website']  as String? ?? '';
  }

  @override
  void dispose() {
    _headlineCtrl.dispose();
    _summaryCtrl.dispose();
    _phoneCtrl.dispose();
    _websiteCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    try {
      await _api.updateProfessionalProfile({
        'headline': _headlineCtrl.text.trim(),
        'summary':  _summaryCtrl.text.trim(),
        'phone':    _phoneCtrl.text.trim(),
        'website':  _websiteCtrl.text.trim(),
      });
      await context.read<AuthService>().refreshProfile();
      if (!mounted) return;
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Professional profile updated.')),
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

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'You will need to sign in with LinkedIn again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Sign out',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AuthService>().logout();
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppConstants.routeLogin,
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
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
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
        ],
      ),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 100),
              children: [
                _ProfileHeader(user: user),
                const SizedBox(height: AppSpacing.lg),
                _isEditing
                    ? _EditForm(
                        headlineCtrl: _headlineCtrl,
                        summaryCtrl:  _summaryCtrl,
                        phoneCtrl:    _phoneCtrl,
                        websiteCtrl:  _websiteCtrl,
                      )
                    : _ViewForm(user: user),
                const SizedBox(height: AppSpacing.xl),
                _SwitchProfileButton(),
                const SizedBox(height: AppSpacing.md),
                _LogoutButton(onTap: _logout),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
      bottomNavigationBar: _BottomNav(),
    );
  }
}

// ─────────────────────────────────────────
// Profile Header
// ─────────────────────────────────────────
class _ProfileHeader extends StatelessWidget {
  final Map<String, dynamic> user;
  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final name      = user['name']            as String? ?? '';
    final headline  = user['headline']        as String? ?? '';
    final avatarUrl = user['profile_picture'] as String?;

    return Column(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: AppColors.primaryLight,
          backgroundImage:
              avatarUrl != null ? NetworkImage(avatarUrl) : null,
          child: avatarUrl == null
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'S',
                  style: const TextStyle(
                      fontSize: 24,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(name, style: AppTextStyles.displaySmall),
        if (headline.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(headline,
              style: AppTextStyles.bodySecondary,
              textAlign: TextAlign.center),
        ],
        const SizedBox(height: AppSpacing.sm),
        // LinkedIn badge
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: const Color(0xFF0A66C2).withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A66C2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Center(
                  child: Text('in',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text('Connected via LinkedIn',
                  style: AppTextStyles.caption
                      .copyWith(color: const Color(0xFF0A66C2))),
            ],
          ),
        ),
      ],
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
    final headline = user['headline'] as String?;
    final summary  = user['summary']  as String?;
    return Column(
      children: [
        // Only show headline/summary if LinkedIn user AND value exists
        if (headline != null && headline.isNotEmpty)
          _InfoTile(icon: Icons.work_rounded, label: 'Headline', value: headline),
        if (summary != null && summary.isNotEmpty)
          _InfoTile(icon: Icons.article_rounded, label: 'Summary', value: summary),
        _InfoTile(
          icon: Icons.email_rounded,
          label: 'Email',
          value: user['email'] as String? ?? '-',
        ),
        _InfoTile(
          icon: Icons.phone_rounded,
          label: 'Phone',
          value: user['phone'] as String? ?? '-',
        ),
        _InfoTile(
          icon: Icons.language_rounded,
          label: 'Website',
          value: user['website'] as String? ?? '-',
        ),
      ],
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
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
// Edit Mode
// ─────────────────────────────────────────
class _EditForm extends StatelessWidget {
  final TextEditingController headlineCtrl;
  final TextEditingController summaryCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController websiteCtrl;

  const _EditForm({
    required this.headlineCtrl,
    required this.summaryCtrl,
    required this.phoneCtrl,
    required this.websiteCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Field(
          ctrl: phoneCtrl,
          label: 'Phone',
          hint: '+1 555 000 0000',
          icon: Icons.phone_rounded,
          keyboardType: TextInputType.phone,
        ),
        _Field(
          ctrl: websiteCtrl,
          label: 'Website',
          hint: 'https://yoursite.com',
          icon: Icons.language_rounded,
          keyboardType: TextInputType.url,
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final IconData icon;
  final int maxLines;
  final TextInputType keyboardType;

  const _Field({
    required this.ctrl,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
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
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// Switch to Public Profile button
// ─────────────────────────────────────────
class _SwitchProfileButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context)
          .pushReplacementNamed(AppConstants.routeEditProfile),
      icon: const Icon(Icons.person_rounded),
      label: const Text('Edit Public Profile'),
    );
  }
}

// ─────────────────────────────────────────
// Logout button
// ─────────────────────────────────────────
class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LogoutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(Icons.logout_rounded, color: AppColors.error),
      label: Text('Sign out',
          style: TextStyle(color: AppColors.error)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: AppColors.error.withOpacity(0.4)),
      ),
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
