import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../data/models/establishment.dart';
import '../data/services/offline_service.dart';
import '../data/services/sync_service.dart';

class PendingInspectionsProvider extends ChangeNotifier {
  static const _lastSyncedKey = 'last_synced_at';

  PendingInspectionsProvider() {
    // Restore persisted timestamp so the label survives cold app restarts
    final stored = OfflineService.readPref(_lastSyncedKey);
    if (stored != null) {
      _lastSyncedAt = DateTime.tryParse(stored);
    }
    _loadPendingCount();
    // Listen to Hive box changes
    OfflineService.inspectionsQueueBox
        .listenable()
        .addListener(_loadPendingCount);
    Hive.box<Establishment>(OfflineService.establishmentsBoxName)
        .listenable()
        .addListener(_loadPendingCount);
  }

  int _pendingCount = 0;
  bool _isSyncing = false;
  String? _syncingId; // Track which specific item is syncing
  DateTime? _lastSyncedAt; // Timestamp of the last successful sync

  int get pendingCount => _pendingCount;
  bool get isEmpty => _pendingCount == 0;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool isItemSyncing(String id) => _isSyncing && _syncingId == id;

  /// Returns a human-readable string like "2 mins ago" or null if never synced.
  String? get lastSyncedLabel {
    if (_lastSyncedAt == null) return null;
    final diff = DateTime.now().difference(_lastSyncedAt!);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  List<MapEntry<dynamic, String>> get pendingItems {
    return OfflineService.inspectionsQueueBox.toMap().entries.toList();
  }

  // [REF: PENDING_COUNTER]
  void _loadPendingCount() {
    int inspectionCount = OfflineService.inspectionsQueueBox.length;
    int estCount = OfflineService.getLocalEstablishments().where((e) => !e.isSynced).length;
    _pendingCount = inspectionCount + estCount;
    notifyListeners();
  }

  // [REF: SYNC_ALL_TRIGGER]
  Future<bool> submitAll() async {
    if (isEmpty || _isSyncing) return false;

    _isSyncing = true;
    _syncingId = null;
    notifyListeners();

    try {
      final successInspections = await SyncService.syncPendingInspections();
      final successEsts = await SyncService.syncPendingEstablishments();
      
      final success = successInspections && successEsts;

      if (success) {
        _lastSyncedAt = DateTime.now();
        // Persist so the label survives app restarts
        await OfflineService.writePref(
          _lastSyncedKey,
          _lastSyncedAt!.toIso8601String(),
        );
      }

      // Reload count just in case
      _loadPendingCount();

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
      if (success) {
        _lastSyncedAt = DateTime.now();
        await OfflineService.writePref(
          _lastSyncedKey,
          _lastSyncedAt!.toIso8601String(),
        );
      }
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
    Hive.box<Establishment>(OfflineService.establishmentsBoxName)
        .listenable()
        .removeListener(_loadPendingCount);
    super.dispose();
  }
}
