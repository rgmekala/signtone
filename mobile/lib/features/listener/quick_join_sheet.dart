import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../auth/auth_service.dart';

/// Slides up when a beacon is detected but user has no JWT.
/// Uses the EXACT same AuthService methods already in the codebase:
///   - loginAsGuest(displayName, email)
///   - loginWithGoogle()
///   - loginWithLinkedIn()
class QuickJoinSheet extends StatefulWidget {
  final String eventName;
  final VoidCallback onJoined;   // called after JWT is saved → go to confirm
  final VoidCallback onDismiss;  // called if user taps "Not now"

  const QuickJoinSheet({
    super.key,
    required this.eventName,
    required this.onJoined,
    required this.onDismiss,
  });

  @override
  State<QuickJoinSheet> createState() => _QuickJoinSheetState();
}

class _QuickJoinSheetState extends State<QuickJoinSheet> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _quickJoin() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (name.isEmpty || email.isEmpty) {
      setState(() => _error = 'Please enter your name and email');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }

    setState(() { _loading = true; _error = null; });

    // loginAsGuest matches the exact signature in your AuthService
    final ok = await context.read<AuthService>().loginAsGuest(
      displayName: name,
      email: email,
    );

    if (!mounted) return;
    if (ok) {
      widget.onJoined();
    } else {
      setState(() {
        _loading = false;
        _error = context.read<AuthService>().errorMessage
            ?? 'Could not join - check your connection';
      });
    }
  }

  Future<void> _googleJoin() async {
    setState(() { _loading = true; _error = null; });

    final ok = await context.read<AuthService>().loginWithGoogle();

    if (!mounted) return;
    if (ok) {
      widget.onJoined();
    } else {
      setState(() {
        _loading = false;
        _error = context.read<AuthService>().errorMessage
            ?? 'Google sign-in failed';
      });
    }
  }

  Future<void> _linkedInJoin() async {
    setState(() { _loading = true; _error = null; });

    final ok = await context.read<AuthService>().loginWithLinkedIn();

    if (!mounted) return;
    if (ok) {
      widget.onJoined();
    } else {
      setState(() {
        _loading = false;
        _error = context.read<AuthService>().errorMessage
            ?? 'LinkedIn sign-in failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Detected badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.graphic_eq_rounded,
                    color: AppColors.primary, size: 15),
                const SizedBox(width: 6),
                Text(
                  'Signtone detected!',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Text(
            'Join ${widget.eventName}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 4),

          const Text(
            'Enter your details to register instantly',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),

          const SizedBox(height: 20),

          // Name
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: _inputDecor('Your name', Icons.person_outline_rounded),
          ),

          const SizedBox(height: 10),

          // Email
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: _inputDecor('Email address', Icons.email_outlined),
          ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],

          const SizedBox(height: 18),

          // Quick Join button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _loading ? null : _quickJoin,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text(
                      'Quick Join →',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 12),

          // Divider
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: TextStyle(color: Colors.grey[400])),
            ),
            const Expanded(child: Divider()),
          ]),

          const SizedBox(height: 12),

          // Google
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Continue with Google'),
              onPressed: _loading ? null : _googleJoin,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // LinkedIn - for professional events
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.work_outline_rounded, size: 18),
              label: const Text('Continue with LinkedIn'),
              onPressed: _loading ? null : _linkedInJoin,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          const SizedBox(height: 4),

          // Not now
          Center(
            child: TextButton(
              onPressed: widget.onDismiss,
              child: const Text('Not now',
                  style: TextStyle(color: Colors.grey)),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecor(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, size: 20),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}
