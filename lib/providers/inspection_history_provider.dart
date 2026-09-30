import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../data/models/inspection_log.dart';
import '../data/services/offline_service.dart';
import '../data/services/sync_service.dart';

class InspectionHistoryProvider extends ChangeNotifier {
  List<InspectionLog> _logs = [];
  List<String> _establishmentNames = [];
  bool _isLoading = false;
  String? _error;

  List<InspectionLog> get logs => _logs;
  List<String> get establishmentNames => _establishmentNames;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isEmpty => _logs.isEmpty;

  /// Returns the establishment name for the log at [index].
  String nameAt(int index) {
    if (index < 0 || index >= _establishmentNames.length) return 'Unknown';
    return _establishmentNames[index];
  }

  // [REF: HISTORY_MERGE_LOCAL_REMOTE]
  Future<void> fetchHistory({int limit = 50}) async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      List<Map<String, dynamic>> rawRemote = [];
      try {
        rawRemote = await SyncService.fetchInspectionHistory(limit: limit);
      } catch (e) {
        debugPrint('Failed to fetch remote history: $e');
        _error = 'Showing offline and cached logs only.';
      }

      final localLogs = OfflineService.inspectionsQueueBox.values.map((jsonString) {
        final Map<String, dynamic> data = jsonDecode(jsonString);
        final log = InspectionLog.fromJson(data);

        // Use the saved name if present (new records include it),
        // otherwise fall back to local Hive cache lookup.
        if (data['establishment_name'] == null || (data['establishment_name'] as String).isEmpty) {
          final est = OfflineService.getEstablishmentById(log.establishmentId);
          data['establishment_name'] = est?.name ?? 'Unknown';
        }
        return data;
      }).toList();

      final combinedRaw = [...localLogs, ...rawRemote];

      final seenIds = <String>{};
      final uniqueRaw = <Map<String, dynamic>>[];
      for (final logData in combinedRaw) {
        final id = logData['id'] as String?;
        if (id != null && !seenIds.contains(id)) {
          seenIds.add(id);
          uniqueRaw.add(logData);
        } else if (id == null) {
           uniqueRaw.add(logData);
        }
      }

      uniqueRaw.sort((a, b) {
        final dateA = a['inspection_date'] as String? ?? '';
        final dateB = b['inspection_date'] as String? ?? '';
        return dateB.compareTo(dateA);
      });

      _logs = uniqueRaw.map((e) => InspectionLog.fromJson(e)).toList();
      _establishmentNames = uniqueRaw
          .map((e) => e['establishment_name'] as String? ?? 'Unknown')
          .toList();
      // Don't clear _error here: if the remote fetch failed above, the
      // "offline and cached logs only" warning must survive to the UI.
    } catch (e) {
      _error = 'Could not load history. Check your connection.';
      debugPrint('InspectionHistoryProvider error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => fetchHistory();
}
