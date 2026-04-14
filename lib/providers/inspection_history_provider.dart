import 'package:flutter/foundation.dart';
import '../data/models/inspection_log.dart';
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

  Future<void> fetchHistory({int limit = 50}) async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final raw = await SyncService.fetchInspectionHistory(limit: limit);
      _logs = raw.map((e) => InspectionLog.fromJson(e)).toList();
      _establishmentNames =
          raw.map((e) => e['establishment_name'] as String? ?? 'Unknown').toList();
      _error = null;
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
