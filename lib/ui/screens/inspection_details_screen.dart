import 'package:flutter/material.dart';
import '../../core/rating_scale.dart';
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
      final results = data['inspection_results'] as List<dynamic>? ?? [];

      // Group by category name (which is now saved as 'sub_category' in Firestore results)
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var result in results) {
        final resMap = result as Map<String, dynamic>;
        
        // In the new Firestore schema, we save 'sub_category' directly on the result doc
        final catName = resMap['sub_category'] as String? ?? 'General';

        if (!grouped.containsKey(catName)) {
          grouped[catName] = [];
        }
        grouped[catName]!.add(resMap);
      }

      setState(() {
        _logData = data;
        _groupedResults = grouped;
        _isLoading = false;
      });
    } catch (e) {
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
    final signatureUrl = _logData!['signature_url'] as String?;

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

        // [REF: SIGNATURE_DISPLAY]
        // Rendered only when the log actually carries a signature: the field
        // is additive (Chunk 7), so legacy logs simply have no key, and a
        // placeholder for them would imply every old record is missing
        // something it was never supposed to have. A queued log whose upload
        // has not finished has no URL yet either — the signature appears here
        // once the queue drains.
        if (signatureUrl != null && signatureUrl.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            "Inspector's Signature",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppTheme.cardRadius,
              boxShadow: AppTheme.softShadow,
            ),
            child: Image.network(
              signatureUrl,
              height: 120,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()),
                    ),
              // Degrades to a quiet note rather than a broken-image glyph —
              // a signature that fails to load offline is expected, not an
              // error state worth alarming over.
              errorBuilder: (context, error, stackTrace) => SizedBox(
                height: 120,
                child: Center(
                  child: Text(
                    'Signature could not be loaded.',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
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
          // Read from the flat Firestore document structure instead of Supabase joined structure
          final question = item['item_name'] as String? ?? 'Unknown Question';
          final status = item['answer'] as String? ?? 'N/A';
          final remarks = item['note'] as String?;

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
