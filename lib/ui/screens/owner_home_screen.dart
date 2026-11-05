import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/rating_scale.dart';
import '../../core/sanitary_order.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/inspection_log.dart';
import '../../providers/auth_provider.dart';
import '../../providers/inspection_history_provider.dart';

// [REF: OWNER_HOME]
//
// What an establishment's point person sees. The only screen in this app
// written for someone who does not work at the City Health Office, which is
// most of what shapes it:
//
//  * It leads with the deadline, because that is the one thing on a Sanitary
//    Order with a consequence attached. Everything else is reference.
//  * It says "demerits" nowhere on the summary. The number means nothing to a
//    carinderia owner; the band label and the list of things to fix do.
//  * Empty and error states explain rather than report. "No inspections yet"
//    with a sentence about what will happen beats an empty list.
//
// Read-only by construction, not by hiding buttons: there is no owner
// insert/update/delete policy on any table (02_rls.sql), so there is nothing
// this screen could offer that the database would accept.
class OwnerHomeScreen extends StatefulWidget {
  const OwnerHomeScreen({super.key});

  @override
  State<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends State<OwnerHomeScreen> {
  @override
  void initState() {
    super.initState();
    // fetchOwnerHistory, never fetchHistory: the latter merges the device's
    // local offline queue, which holds whatever the inspector using this phone
    // has not synced — another establishment's inspection, on this owner's
    // screen, with no server involved to refuse it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<InspectionHistoryProvider>().fetchOwnerHistory();
      }
    });
  }

  // [REF: OWNER_CURRENT_ORDER]
  /// The order from the MOST RECENT inspection, if that inspection issued one.
  /// Null when the latest visit issued nothing.
  ///
  /// Deliberately not "the soonest deadline on record", which is what this
  /// did first and which made the red banner permanent: an establishment
  /// ordered in January, which complied and passed a clean re-inspection in
  /// March, still owns that January log — so the home screen led forever with
  /// "Action overdue / The deadline has passed" pointing at a closed order.
  ///
  /// Nothing in this system records compliance: an order has no "resolved"
  /// flag, and the re-inspection the form promises is just another inspection.
  /// So the honest reading of the record is the latest one. A later clean
  /// inspection supersedes an earlier order; a later order supersedes an
  /// earlier order. An overdue banner then means the last thing that happened
  /// here was an unmet order, which is true.
  ///
  /// [logs] arrives newest-first (InspectionHistoryProvider sorts by
  /// inspection_date descending), so this is the head of the list.
  ({InspectionLog log, DateTime deadline, int defects})? _currentOrder(
      List<InspectionLog> logs) {
    if (logs.isEmpty) return null;
    final latest = logs.first;
    if (latest.soIssuedAt == null || latest.deadline == null) return null;
    final due = DateTime.tryParse(latest.deadline!);
    if (due == null) return null;
    return (
      log: latest,
      deadline: due,
      defects: SanitaryOrder.defectsFrom(latest.results).length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<InspectionHistoryProvider>();
    final logs = history.logs;
    final due = _currentOrder(logs);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textDisplay,
        elevation: 0,
        title: const Text(
          'My Inspections',
          style: TextStyle(
            fontFamily: '.SF Pro Display',
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => context.read<AuthProvider>().signOut(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () =>
            context.read<InspectionHistoryProvider>().fetchOwnerHistory(),
        child: history.isLoading && logs.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                // Always scrollable so pull-to-refresh works even when the
                // list is empty — which is exactly when someone waiting for
                // their results will try it.
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  _buildWelcome(logs, history),
                  if (due != null) ...[
                    const SizedBox(height: 16),
                    _buildDeadlineCard(due),
                  ],
                  const SizedBox(height: 24),
                  if (logs.isEmpty)
                    _buildEmptyState(history)
                  else ...[
                    const Text(
                      'Inspection history',
                      style: TextStyle(
                        fontFamily: '.SF Pro Display',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDisplay,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(
                      logs.length,
                      (i) => _buildLogCard(logs[i], history.nameAt(i)),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildWelcome(
      List<InspectionLog> logs, InspectionHistoryProvider history) {
    // The establishment name off the most recent log rather than a separate
    // lookup: the log denormalises it at write time precisely so no reader
    // needs a join, and an owner mapped to several establishments sees each
    // name on its own card below anyway.
    final name = logs.isEmpty ? null : history.nameAt(0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: AppTheme.cardRadius,
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_rounded,
                  size: 20, color: AppColors.brandStrong),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name ?? 'Your establishment',
                  style: const TextStyle(
                    fontFamily: '.SF Pro Display',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandStrong,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'This is your record of every sanitary inspection by the City '
            'Health Office. Only you and the office can see it.',
            style: TextStyle(
              fontFamily: '.SF Pro Text',
              fontSize: 13,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// The one card with a consequence attached, so it gets the strongest
  /// treatment on the screen — and an honest one: a passed deadline is shown
  /// as passed rather than quietly rendered in the same calm green.
  Widget _buildDeadlineCard(
      ({InspectionLog log, DateTime deadline, int defects}) due) {
    final today = DateTime.now();
    final daysLeft =
        DateTime(due.deadline.year, due.deadline.month, due.deadline.day)
            .difference(DateTime(today.year, today.month, today.day))
            .inDays;
    final overdue = daysLeft < 0;

    final accent = overdue
        ? AppColors.fail
        : daysLeft <= 3
            ? const Color(0xFFF59E0B) // amber, the verySatisfactory token
            : AppColors.brandStrong;

    final String when;
    if (overdue) {
      when = 'The deadline has passed';
    } else if (daysLeft == 0) {
      when = 'Due today';
    } else if (daysLeft == 1) {
      when = '1 day left';
    } else {
      when = '$daysLeft days left';
    }

    return InkWell(
      borderRadius: AppTheme.cardRadius,
      onTap: () => context.push(
        '/inspection/details/${due.log.id}',
        extra: due.log.establishmentName ?? 'Your establishment',
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppTheme.cardRadius,
          border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
          boxShadow: AppTheme.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  overdue
                      ? Icons.warning_amber_rounded
                      : Icons.event_available_rounded,
                  size: 20,
                  color: accent,
                ),
                const SizedBox(width: 8),
                Text(
                  overdue ? 'Action overdue' : 'Action needed',
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: accent,
                  ),
                ),
                const Spacer(),
                Text(
                  when,
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              due.defects == 1
                  ? 'There is 1 item to correct by '
                      '${_prettyDate(due.deadline)}.'
                  : 'There are ${due.defects} items to correct by '
                      '${_prettyDate(due.deadline)}.',
              style: const TextStyle(
                fontFamily: '.SF Pro Display',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: AppColors.textDisplay,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'See what to fix',
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 15, color: accent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard(InspectionLog log, String establishmentName) {
    final pct = log.percentageRating;
    final band = RatingScale.labelOf(pct);
    final color = RatingScale.colorOf(pct);
    final issuedOrder = log.soIssuedAt != null;
    final date = DateTime.tryParse(log.inspectionDate);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: AppTheme.cardRadius,
        onTap: () => context.push(
          '/inspection/details/${log.id}',
          extra: establishmentName,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppTheme.cardRadius,
            border: Border.all(color: AppColors.border),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            children: [
              // The score, in its band colour. No demerit count: it is the
              // complement of this number and means nothing on its own to
              // someone who has not read the scoring rules.
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  pct == null ? '—' : '${pct.round()}',
                  style: TextStyle(
                    fontFamily: '.SF Pro Display',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date == null ? 'Date not recorded' : _prettyDate(date),
                      style: const TextStyle(
                        fontFamily: '.SF Pro Display',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDisplay,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      band,
                      style: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    if (issuedOrder) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.fail.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.gavel_rounded,
                                size: 12, color: AppColors.fail),
                            const SizedBox(width: 4),
                            Text(
                              log.soNo == null
                                  ? 'Sanitary Order'
                                  : 'Sanitary Order No. ${log.soNo}',
                              style: const TextStyle(
                                fontFamily: '.SF Pro Text',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.fail,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.borderStrong),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(InspectionHistoryProvider history) {
    // An error and an empty record are different things and must not look the
    // same: one means "try again", the other means "nothing has happened yet".
    final failed = history.error != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppTheme.cardRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.brandSurface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              failed ? Icons.wifi_off_rounded : Icons.inbox_rounded,
              size: 28,
              color: AppColors.brandStrong,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            failed ? 'Could not load your records' : 'No inspections yet',
            style: const TextStyle(
              fontFamily: '.SF Pro Display',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textDisplay,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            failed
                ? 'Check your internet connection, then pull down to try '
                    'again.'
                : 'When a City Health inspector visits your establishment, '
                    'the results will appear here.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: '.SF Pro Text',
              fontSize: 13,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  static const List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// "30 October 2026". Spelled out rather than 2026-10-30: this screen is
  /// read by someone who is not reading a database.
  static String _prettyDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';
}
