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
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: AppTheme.cardRadius,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.assignment_late_rounded,
                color: Colors.white.withValues(alpha: 0.9),
                size: 24,
              ),
            ),
            // Body
            if (provider.isEmpty)
              const Text(
                'No pending\ninspection results',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
              )
            else ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${provider.pendingCount}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.0,
                      letterSpacing: -1,
                    ),
                  ),
                  const Text(
                    'Pending\nInspections',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white70,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: double.infinity,
                height: 32,
                child: ElevatedButton(
                  onPressed: provider.isSyncing ? null : onSubmitAll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: theme.colorScheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: provider.isSyncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Submit All'),
                ),
              ),
            ],
          ],
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
                                                  if (provider.isEmpty) Navigator.pop(context);
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
