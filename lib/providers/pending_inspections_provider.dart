import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../data/services/offline_service.dart';
import '../data/services/sync_service.dart';

class PendingInspectionsProvider extends ChangeNotifier {
  PendingInspectionsProvider() {
    _loadPendingCount();
    // Listen to Hive box changes
    OfflineService.inspectionsQueueBox
        .listenable()
        .addListener(_loadPendingCount);
  }

  int _pendingCount = 0;
  bool _isSyncing = false;
  String? _syncingId; // Track which specific item is syncing

  int get pendingCount => _pendingCount;
  bool get isEmpty => _pendingCount == 0;
  bool get isSyncing => _isSyncing;
  bool isItemSyncing(String id) => _isSyncing && _syncingId == id;

  List<MapEntry<dynamic, String>> get pendingItems {
    return OfflineService.inspectionsQueueBox.toMap().entries.toList();
  }

  void _loadPendingCount() {
    _pendingCount = OfflineService.inspectionsQueueBox.length;
    notifyListeners();
  }

  Future<bool> submitAll() async {
    if (isEmpty || _isSyncing) return false;

    _isSyncing = true;
    _syncingId = null;
    notifyListeners();

    try {
      final success = await SyncService.syncPendingInspections();
      return success;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<bool> submitSingle(String id) async {
    if (_isSyncing) return false;

    _isSyncing = true;
    _syncingId = id;
    notifyListeners();

    try {
      final success = await SyncService.syncSingleInspection(id);
      return success;
    } finally {
      _isSyncing = false;
      _syncingId = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    OfflineService.inspectionsQueueBox
        .listenable()
        .removeListener(_loadPendingCount);
    super.dispose();
  }
}
