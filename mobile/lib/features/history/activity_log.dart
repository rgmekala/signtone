import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../shared/services/api_client.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final _api = ApiClient();

  late Future<List<Map<String, dynamic>>> _registrationsFuture;

  @override
  void initState() {
    super.initState();
    _registrationsFuture = _api.getMyRegistrations();
  }

  void _refresh() {
    setState(() {
      _registrationsFuture = _api.getMyRegistrations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _registrationsFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorState(onRetry: _refresh);
          }
          final items = snap.data ?? [];
          if (items.isEmpty) return const _EmptyState();
          return _RegistrationList(items: items);
        },
      ),
      bottomNavigationBar: _BottomNav(),
    );
  }
}

// ─────────────────────────────────────────
// Registration List
// ─────────────────────────────────────────
class _RegistrationList extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _RegistrationList({required this.items});

  @override
  Widget build(BuildContext context) {
    // Group by date
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final dateKey = _dateLabel(item['registered_at'] as String?);
      grouped.putIfAbsent(dateKey, () => []).add(item);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      itemCount: grouped.length,
      itemBuilder: (context, i) {
        final dateKey = grouped.keys.elementAt(i);
        final dayItems = grouped[dateKey]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
              child: Text(dateKey,
                  style: AppTextStyles.label
                      .copyWith(color: AppColors.textSecondary)),
            ),
            ...dayItems.map((item) => _RegistrationCard(data: item)),
          ],
        );
      },
    );
  }

  String _dateLabel(String? iso) {
    if (iso == null) return 'Unknown date';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return 'Unknown date';
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(dt.year, dt.month, dt.day))
        .inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${_month(dt.month)} ${dt.day}, ${dt.year}';
  }

  String _month(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}

// ─────────────────────────────────────────
// Registration Card
// ─────────────────────────────────────────
class _RegistrationCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _RegistrationCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final eventName    = data['event_name']    as String? ?? 'Unknown Event';
    final eventType    = data['event_type']    as String? ?? 'conference';
    final profileType  = data['profile_type']  as String? ?? 'professional';
    final organizer    = data['organizer_name'] as String? ?? '';
    final registeredAt = data['registered_at']  as String?;
    final timeStr      = _timeString(registeredAt);

    final (typeColor, typeLabel, typeIcon) = _eventTypeMeta(eventType);
    final isProfessional =
        profileType == AppConstants.profileTypeProfessional;

    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event type icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(typeIcon, color: typeColor, size: 22),
            ),

            const SizedBox(width: AppSpacing.md),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Event name + time
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(eventName,
                            style: AppTextStyles.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(timeStr, style: AppTextStyles.caption),
                    ],
                  ),

                  if (organizer.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(organizer, style: AppTextStyles.caption),
                  ],

                  const SizedBox(height: AppSpacing.sm),

                  // Pills row
                  Row(
                    children: [
                      // Event type pill
                      _Pill(
                        label: typeLabel,
                        color: typeColor,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      // Profile type pill
                      _Pill(
                        label: isProfessional ? 'Professional' : 'Public',
                        color: isProfessional
                            ? AppColors.primary
                            : AppColors.accent,
                        icon: isProfessional
                            ? Icons.badge_rounded
                            : Icons.person_rounded,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeString(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  (Color, String, IconData) _eventTypeMeta(String type) =>
      switch (type) {
        'sweepstake' => (
            AppColors.warning,
            'Sweepstake',
            Icons.emoji_events_rounded
          ),
        'broadcast' => (
            AppColors.accent,
            'Broadcast',
            Icons.radio_rounded
          ),
        _ => (
            AppColors.primary,
            'Conference',
            Icons.business_center_rounded
          ),
      };
}

// ─────────────────────────────────────────
// Pill badge
// ─────────────────────────────────────────
class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const _Pill({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(label,
              style: AppTextStyles.caption.copyWith(
                  color: color, fontWeight: FontWeight.w600, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history_rounded,
                size: 40, color: AppColors.textHint),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('No registrations yet', style: AppTextStyles.headline),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Start listening and register for\nyour first event.',
            style: AppTextStyles.bodySecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: 200,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context)
                  .pushReplacementNamed(AppConstants.routeHome),
              icon: const Icon(Icons.mic_rounded),
              label: const Text('Start Listening'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// Error State
// ─────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 48, color: AppColors.textHint),
          const SizedBox(height: AppSpacing.md),
          Text('Could not load history', style: AppTextStyles.headline),
          const SizedBox(height: AppSpacing.sm),
          Text('Check your connection and try again.',
              style: AppTextStyles.bodySecondary),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: 160,
            child: ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ),
        ],
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
      currentIndex: 1,
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
