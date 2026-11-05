import 'package:flutter/material.dart';
import '../../core/rating_scale.dart';
import '../../core/sanitary_order.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/sync_service.dart';
import '../../core/theme/app_colors.dart';

class InspectionDetailsScreen extends StatefulWidget {
  final String logId;
  final String establishmentName;

  const InspectionDetailsScreen({
    super.key,
    required this.logId,
    required this.establishmentName,
  });

  @override
  State<InspectionDetailsScreen> createState() => _InspectionDetailsScreenState();
}

class _InspectionDetailsScreenState extends State<InspectionDetailsScreen> {
  Map<String, dynamic>? _logData;
  Map<String, List<Map<String, dynamic>>> _groupedResults = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  // [REF: INSPECTION_DETAILS_VIEW]
  Future<void> _fetchDetails() async {
    try {
      final data = await SyncService.fetchInspectionDetails(widget.logId);
      // Per-item answers live in the `results` jsonb array on the log row —
      // the same key both clients write.
      final results = data['results'] as List<dynamic>? ?? [];

      // Group by sub_category: every result row denormalizes it at submit
      // time (see the results-array builder in inspection_form_screen).
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var result in results) {
        final resMap = Map<String, dynamic>.from(result as Map);
        final catName = resMap['sub_category'] as String? ?? 'General';

        if (!grouped.containsKey(catName)) {
          grouped[catName] = [];
        }
        grouped[catName]!.add(resMap);
      }

      // Pre-dating the Sanitary Order work, and guarded now because this
      // screen is one tap from two different lists: popping it while the
      // fetch is in flight — ordinary on a slow connection — reached
      // setState on a dead State and threw.
      if (!mounted) return;
      setState(() {
        _logData = data;
        _groupedResults = grouped;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load inspection details.';
        _isLoading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'compliant':
      case 'pass':
        return AppColors.pass;
      case 'non-compliant':
      case 'fail':
        return AppColors.fail;
      case 'n/a':
      default:
        return Colors.grey.shade600;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'compliant':
      case 'pass':
        return Icons.check_circle_rounded;
      case 'non-compliant':
      case 'fail':
        return Icons.cancel_rounded;
      case 'n/a':
      default:
        return Icons.remove_circle_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspection Details'),
        backgroundColor: Colors.white,
        foregroundColor: primary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 1),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 48, color: Colors.red.shade300),
                      const SizedBox(height: 16),
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _error = null;
                          });
                          _fetchDetails();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _buildContent(primary),
    );
  }

  Widget _buildContent(Color primary) {
    if (_logData == null) return const SizedBox.shrink();

    // Left nullable on purpose: a log with no `percentage_rating` has not been
    // scored, which RatingScale renders as "Not Scored Yet" rather than a red 0%.
    final pct = (_logData!['percentage_rating'] as num?)?.toDouble();
    final demerits = _logData!['total_demerits'] as int? ?? 0;
    final inspector = _logData!['inspector_name'] as String? ?? 'Unknown';
    final remarks = _logData!['remarks'] as String?;

    // The order, when this inspection issued one. so_issued_at is the marker,
    // not so_no: the number is typed off CHO's pre-numbered booklet and may
    // legitimately be blank on a real order.
    final soIssuedAt = _logData!['so_issued_at'] as String?;

    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        // Summary Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppTheme.cardRadius,
            boxShadow: AppTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.establishmentName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Inspector: $inspector',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // [REF: RATING_SCALE] value, caption and band all agree
                  _buildStatItem(
                    'Rating',
                    pct == null ? '—' : '${pct.toStringAsFixed(1)}%',
                    RatingScale.colorOf(pct),
                    band: RatingScale.labelOf(pct),
                  ),
                  _buildStatItem(
                      'Demerits', '$demerits', Colors.orange.shade700),
                ],
              ),
              if (remarks != null && remarks.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Remarks',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  remarks,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ],
          ),
        ),
        if (soIssuedAt != null) ...[
          const SizedBox(height: 24),
          _buildSanitaryOrderCard(),
        ],
        const SizedBox(height: 24),
        const Text(
          'Checklist Results',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        if (_groupedResults.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text(
                'No checklist results recorded.',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          )
        else
          ..._groupedResults.entries.map((entry) {
            return _buildCategorySection(entry.key, entry.value);
          }),

      ],
    );
  }

  /// [band], when given, is printed under the caption in the value's colour —
  /// used by the rating so the number, its colour and its band name sit together.
  Widget _buildStatItem(String label, String value, Color color, {String? band}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        if (band != null)
          Text(
            band,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
      ],
    );
  }

  // [REF: SO_DETAILS_CARD]
  /// The Sanitary Order's own facts, for whoever is reading the record.
  ///
  /// Not a reproduction of CHO-ESD-FR-04 — the printable form lives in the web
  /// admin, and the signed paper is already in the recipient's hands. What is
  /// here is the part with a consequence: how many items, by when.
  Widget _buildSanitaryOrderCard() {
    final soNo = _logData!['so_no'] as String?;
    final timeGiven = _logData!['time_given'] as String?;
    final deadline = _logData!['deadline'] as String?;
    final receivedBy = _logData!['received_by_name'] as String?;
    final results = (_logData!['results'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final defects = SanitaryOrder.defectsFrom(results);

    final due = deadline == null ? null : DateTime.tryParse(deadline);
    final overdue = due != null &&
        DateTime(due.year, due.month, due.day).isBefore(
          DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppTheme.cardRadius,
        border: Border.all(color: AppColors.fail.withValues(alpha: 0.30)),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel_rounded, size: 18, color: AppColors.fail),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  soNo == null
                      ? 'Sanitary Order issued'
                      : 'Sanitary Order No. $soNo',
                  style: const TextStyle(
                    fontFamily: '.SF Pro Display',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDisplay,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            defects.length == 1
                ? '1 item must be corrected.'
                : '${defects.length} items must be corrected.',
            style: const TextStyle(
              fontFamily: '.SF Pro Text',
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          if (timeGiven != null && timeGiven.isNotEmpty)
            _buildOrderRow('Time given', timeGiven, AppColors.textPrimary),
          if (deadline != null)
            _buildOrderRow(
              'Deadline',
              overdue ? '$deadline (passed)' : deadline,
              overdue ? AppColors.fail : AppColors.textPrimary,
            ),
          if (receivedBy != null && receivedBy.isNotEmpty)
            _buildOrderRow('Received by', receivedBy, AppColors.textPrimary),
          const SizedBox(height: 4),
          const Text(
            'A re-inspection follows the deadline to check compliance.',
            style: TextStyle(
              fontFamily: '.SF Pro Text',
              fontSize: 11,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(String categoryName, List<Map<String, dynamic>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            categoryName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        ...items.map((item) {
          // Each result row is self-describing (item_name/answer/note are
          // denormalized at submit) — no join back to checklist_templates.
          final question = item['item_name'] as String? ?? 'Unknown Question';
          final status = item['answer'] as String? ?? 'N/A';
          final remarks = item['note'] as String?;
          // The right-hand column of the Sanitary Order: what the
          // establishment is ordered to do about this defect. Written since
          // the order existed; absent on every log from before it, which is
          // why it renders only when present rather than as an empty row.
          final correction = item['correction'] as String?;
          // The item's extra inputs (ChecklistField), label -> value. Lists
          // are multi-selects; blanks were never filled and are not shown.
          final values = ((item['values'] as Map?) ?? const {})
              .entries
              .where((e) => e.value is List
                  ? (e.value as List).isNotEmpty
                  : (e.value?.toString() ?? '').isNotEmpty)
              .map((e) => MapEntry(
                  e.key.toString(),
                  e.value is List ? (e.value as List).join(', ') : e.value.toString()))
              .toList();

          final color = _statusColor(status);
          final icon = _statusIcon(status);

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          question,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 14, color: color),
                            const SizedBox(width: 4),
                            Text(
                              status,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  for (final v in values)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${v.key}: ${v.value}',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700)),
                    ),
                  if (remarks != null && remarks.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      remarks,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  // Set apart from the note rather than appended to it: one
                  // is what is wrong, the other is what has to be done, and
                  // on the order itself they are two separate columns.
                  if (correction != null && correction.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.brandSurface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.build_circle_outlined,
                              size: 15, color: AppColors.brandStrong),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'What to do',
                                  style: TextStyle(
                                    fontFamily: '.SF Pro Text',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                    color: AppColors.brandStrong,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  correction,
                                  style: const TextStyle(
                                    fontFamily: '.SF Pro Text',
                                    fontSize: 13,
                                    height: 1.4,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }
}
