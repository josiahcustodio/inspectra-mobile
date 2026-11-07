import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../data/models/inspection_log.dart';
import '../data/services/offline_service.dart';
import '../data/services/sync_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InspectionHistoryProvider extends ChangeNotifier {
  List<InspectionLog> _logs = [];
  List<String> _establishmentNames = [];
  bool _isLoading = false;
  String? _error;

  InspectionHistoryProvider() {
    // Supabase.instance throws before initialize(); tests build this provider
    // bare, and they have no session to clear anyway.
    try {
      Supabase.instance.client.auth.onAuthStateChange.listen((s) {
        if (s.event == AuthChangeEvent.signedOut) clear();
      });
    } catch (_) {}
  }

  /// Bumped by clear(); a fetch started before the bump drops its result.
  int _generation = 0;

  void clear() {
    _generation++;
    _isLoading = false; // a fetch still in flight will drop its result
    _logs = [];
    _establishmentNames = [];
    _error = null;
    notifyListeners();
  }

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
  /// [includeLocalQueue] MUST be false for an establishment owner.
  ///
  /// The remote half of this merge is scoped by RLS, so the server can only
  /// ever hand an owner their own establishments' logs. The local half is not:
  /// `inspectionsQueueBox` is a device-global Hive box holding whatever the
  /// inspector using this phone has not synced yet. Merging it into an owner's
  /// list would show them another establishment's inspection — its score, its
  /// defects, its remarks — with no server involved to say no.
  ///
  /// Reachable the first time an inspector hands their phone to an owner to
  /// look something up, which is exactly the situation the owner view exists
  /// for.
  Future<void> fetchHistory({
    int limit = 50,
    bool includeLocalQueue = true,
  }) async {
    if (_isLoading) return;
    final generation = _generation;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      List<Map<String, dynamic>> rawRemote = [];
      String? remoteError;
      try {
        rawRemote = await SyncService.fetchInspectionHistory(limit: limit);
      } catch (e) {
        debugPrint('Failed to fetch remote history: $e');
        remoteError = 'Showing offline and cached logs only.';
      }

      final localLogs = !includeLocalQueue
          ? <Map<String, dynamic>>[]
          : OfflineService.inspectionsQueueBox.values.map((jsonString) {
              final Map<String, dynamic> data = jsonDecode(jsonString);
              final log = InspectionLog.fromJson(data);

              // Use the saved name if present (new records include it),
              // otherwise fall back to local Hive cache lookup.
              if (data['establishment_name'] == null ||
                  (data['establishment_name'] as String).isEmpty) {
                final est =
                    OfflineService.getEstablishmentById(log.establishmentId);
                data['establishment_name'] = est?.name ?? 'Unknown';
              }
              return data;
            }).toList();

      // Signed out while the request was out: these rows belong to the
      // previous user, so leave the cleared state alone.
      if (generation != _generation) return;
      _error = remoteError;

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
      if (generation == _generation) _error = 'Could not load history. Check your connection.';
      debugPrint('InspectionHistoryProvider error: $e');
    } finally {
      // clear() already reset and notified; a newer fetch may be running.
      if (generation == _generation) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() => fetchHistory();

  /// The owner-safe fetch: server rows only, so nothing another inspector
  /// staged on this device can reach an owner's screen.
  Future<void> fetchOwnerHistory({int limit = 50}) =>
      fetchHistory(limit: limit, includeLocalQueue: false);
}
