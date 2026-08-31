import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pending_inspections_provider.dart';

class PendingCard extends StatelessWidget {
  final PendingInspectionsProvider provider;
  final ThemeData theme;
  final VoidCallback onSubmitAll;

  const PendingCard({
    super.key,
    required this.provider,
    required this.theme,
    required this.onSubmitAll,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: provider.isEmpty ? null : () => _showPendingModal(context, provider),
      borderRadius: AppTheme.cardRadius,
      child: Container(
        decoration: AppTheme.glassDecoration(Colors.white),
        child: Padding(
          padding: const EdgeInsets.all(12), // Reduced padding to fit 140px bento height
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Pending',
                    style: TextStyle(
                      fontFamily: '.SF Pro Text',
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(Icons.sync_rounded, color: provider.isSyncing ? AppTheme.primary : Colors.grey.shade400, size: 16),
                ],
              ),
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 48, // Reduced from 64
                      height: 48,
                      child: CircularProgressIndicator(
                        value: provider.isEmpty ? 0 : 0.65,
                        backgroundColor: Colors.grey.shade100,
                        color: AppTheme.primary,
                        strokeWidth: 5,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Text(
                      '${provider.pendingCount}',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 20, // Reduced from 24
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        height: 1.0,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 28, // Reduced from 32
                    child: OutlinedButton(
                      onPressed: provider.isSyncing || provider.isEmpty ? null : onSubmitAll,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: AppTheme.primaryDark,
                        side: const BorderSide(color: AppTheme.primary, width: 1.5), // Crisp Emerald border
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: provider.isSyncing
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primaryDark,
                              ))
                          : const Text(
                              'Sync Now',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800, // High-contrast text
                                color: AppTheme.primaryDark,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    provider.lastSyncedLabel != null
                        ? 'Last synced: ${provider.lastSyncedLabel}'
                        : 'Never synced',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPendingModal(BuildContext context, PendingInspectionsProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Consumer<PendingInspectionsProvider>(
                builder: (context, provider, _) {
                  if (provider.isEmpty) {
                    return const Center(child: Text('No pending inspections.'));
                  }

                  return Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Pending Inspections', style: theme.textTheme.titleLarge),
                            ElevatedButton(
                              onPressed: provider.isSyncing ? null : onSubmitAll,
                              child: const Text('Submit All'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollController,
                          itemCount: provider.pendingCount,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = provider.pendingItems[index];
                            final String key = entry.key;
                            final isSyncingThis = provider.isItemSyncing(key);

                            return ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.assignment_late)),
                              title: Text('Inspection: $key'),
                              trailing: isSyncingThis
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2))
                                  : ElevatedButton(
                                      onPressed: provider.isSyncing
                                          ? null
                                          : () async {
                                              final success = await provider.submitSingle(key);
                                              if (context.mounted) {
                                                if (success) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(content: Text('Synced Successfully!')));
                                                  if (provider.isEmpty) context.pop();
                                                } else {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(content: Text('Failed to sync. Check connection.')));
                                                }
                                              }
                                            },
                                      child: const Text('Submit'),
                                    ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
