import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/rating_scale.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/offline_service.dart';
import '../../providers/pending_inspections_provider.dart';
import '../../providers/inspection_history_provider.dart';
import '../widgets/new_inspection_modal.dart';
import '../widgets/pending_card.dart';
import '../widgets/stat_card.dart';
import 'main_navigation_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estCount = OfflineService.getLocalEstablishments().length;

    // Trigger a history fetch whenever the Home screen is built (once per session).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<InspectionHistoryProvider>();
      if (provider.logs.isEmpty && !provider.isLoading) {
        provider.fetchHistory();
      }
    });

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(theme),
              const SizedBox(height: 24),
              _buildPrimaryAction(context, theme),
              const SizedBox(height: 32),
              _buildBentoLayout(context, theme, estCount),
              const SizedBox(height: 32),
              _buildRecentActivity(context, theme),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────────

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              'Inspector Dashboard',
              style: theme.textTheme.headlineMedium,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade200, width: 2),
            ),
            child: const CircleAvatar(
              radius: 20,
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.secondary,
              child: Icon(Icons.person, size: 24),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Primary Action ───────────────────────────────────────────────────────────

  Widget _buildPrimaryAction(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppTheme.buttonRadius,
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: () => _showNewInspectionModal(context, theme),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_business_rounded),
              SizedBox(width: 12),
              Text(
                'New Inspection',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNewInspectionModal(BuildContext context, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return NewInspectionModal(theme: theme);
      },
    );
  }

  // ─── Bento Layout ─────────────────────────────────────────────────────────────

  // [REF: HOME_STATS]
  Widget _buildBentoLayout(BuildContext context, ThemeData theme, int estCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overview', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero Card — Pending Inspections
                Expanded(
                  flex: 5,
                  child: Consumer<PendingInspectionsProvider>(
                    builder: (context, provider, _) {
                      return PendingCard(
                        provider: provider,
                        theme: theme,
                        onSubmitAll: () => _submitAll(context, provider),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // Stat Card — Establishments
                Expanded(
                  flex: 4,
                  child: StatCard(
                    icon: Icons.storefront_rounded,
                    iconColor: theme.colorScheme.primary,
                    value: estCount.toString(),
                    label: 'Establishments',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitAll(
      BuildContext context, PendingInspectionsProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.submitAll();

    if (!success && !provider.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Waiting for internet connection to sync...'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (success) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('All pending inspections submitted successfully.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ─── Recent Activity ──────────────────────────────────────────────────────────

  // [REF: RECENT_ACTIVITY]
  Widget _buildRecentActivity(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Activity', style: theme.textTheme.titleLarge),
              TextButton(
                onPressed: () {
                  // History tab (branch order: 0 Home, 1 Establishments, 2 History, 3 Profile)
                  MainNavigationScreen.tabNotifier.value = 2;
                },
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                ),
                child: const Text('See All',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Consumer<InspectionHistoryProvider>(
            builder: (context, provider, _) {
              if (provider.isLoading) {
                return Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: AppTheme.cardRadius,
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }

              if (provider.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: AppTheme.cardRadius,
                    boxShadow: AppTheme.softShadow,
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: Center(
                    child: Text(
                      'No recent inspections',
                      style: TextStyle(
                          color: Colors.grey.shade400, fontSize: 14),
                    ),
                  ),
                );
              }

              final recent = provider.logs.take(2).toList();
              return Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: AppTheme.cardRadius,
                  boxShadow: AppTheme.softShadow,
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: recent.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: Colors.grey.shade100,
                    indent: 64,
                  ),
                  itemBuilder: (context, index) {
                    final log = recent[index];
                    final name = provider.nameAt(index);
                    final pct = log.percentageRating;
                    // [REF: RATING_SCALE]
                    final color = RatingScale.colorOf(pct);

                    // Format date
                    String dateStr = log.inspectionDate;
                    try {
                      final dt = DateTime.parse(log.inspectionDate).toLocal();
                      const months = [
                        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
                      ];
                      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
                      final m = dt.minute.toString().padLeft(2, '0');
                      final ap = dt.hour < 12 ? 'AM' : 'PM';
                      dateStr =
                          '${months[dt.month - 1]} ${dt.day}  $h:$m $ap';
                    } catch (_) {}

                    return ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: color,
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          dateStr,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${pct.toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right,
                              color: Colors.grey.shade400),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
