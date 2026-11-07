import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/rating_scale.dart';
import '../../data/models/establishment.dart';
import '../../data/services/offline_service.dart';
import '../../data/services/sync_service.dart';
import '../screens/history_screen.dart' show openInspectionDetails;

// [REF: ESTABLISHMENT_SHEET]
/// Tap an establishment on the map: its past inspections, each openable, and
/// the button to start a new one. Server rows plus whatever is still queued on
/// this phone; offline, only the queue shows and the sheet says so.
void showEstablishmentSheet(BuildContext context, Establishment est) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      expand: false,
      builder: (ctx, scroll) => _EstablishmentSheet(est: est, scroll: scroll),
    ),
  );
}

class _EstablishmentSheet extends StatefulWidget {
  final Establishment est;
  final ScrollController scroll;
  const _EstablishmentSheet({required this.est, required this.scroll});

  @override
  State<_EstablishmentSheet> createState() => _EstablishmentSheetState();
}

class _EstablishmentSheetState extends State<_EstablishmentSheet> {
  List<Map<String, dynamic>>? _logs;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.est.id;
    final queued = <Map<String, dynamic>>[];
    for (final raw in OfflineService.inspectionsQueueBox.values) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        if (m['establishment_id'] == id) queued.add({...m, '_queued': true});
      } catch (_) {}
    }
    var remote = <Map<String, dynamic>>[];
    try {
      remote = await SyncService.fetchLogsForEstablishment(id);
    } catch (_) {
      _offline = true;
    }
    final queuedIds = queued.map((m) => m['id']).toSet();
    final all = [...queued, ...remote.where((m) => !queuedIds.contains(m['id']))];
    all.sort((a, b) => (b['inspection_date'] as String? ?? '').compareTo(a['inspection_date'] as String? ?? ''));
    if (mounted) setState(() => _logs = all);
  }

  String _date(String? iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso).toLocal();
      const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${m[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return iso.split('T').first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final est = widget.est;
    final logs = _logs;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(est.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(est.fullAddress, style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Inspection history', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (_offline)
                    Text('Offline: unsent only', style: TextStyle(color: Colors.orange.shade800, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: logs == null
              ? const Center(child: CircularProgressIndicator())
              : logs.isEmpty
                  ? Center(child: Text('No inspections yet', style: TextStyle(color: Colors.grey.shade600)))
                  : ListView.separated(
                      controller: widget.scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: logs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final m = logs[i];
                        final pct = (m['percentage_rating'] as num?)?.toDouble();
                        final color = RatingScale.colorOf(pct);
                        final queued = m['_queued'] == true;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.15),
                            child: Icon(queued ? Icons.schedule : Icons.check_circle_rounded, color: color),
                          ),
                          title: Text(_date(m['inspection_date'] as String?)),
                          subtitle: Text(
                            [
                              if ((m['category_name'] as String?)?.isNotEmpty == true) m['category_name'],
                              if (m['so_issued_at'] != null) 'Sanitary Order',
                              if (queued) 'Not yet synced · submit it from Home',
                            ].join(' · '),
                          ),
                          enabled: !queued,
                          trailing: Text(
                            pct == null ? '—' : '${pct.toStringAsFixed(0)}%',
                            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          onTap: queued ? null : () => openInspectionDetails(ctx, m['id'] as String, est.name),
                        );
                      },
                    ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                // Resolve the router before pop() unmounts this context.
                final router = GoRouter.of(context);
                Navigator.pop(context);
                // Same entry point as the establishments list.
                router.push('/inspection', extra: est);
              },
              icon: const Icon(Icons.assignment_add),
              label: const Text('Start new inspection'),
            ),
          ),
        ),
      ],
    );
  }
}
