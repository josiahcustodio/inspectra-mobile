import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inspection_log.dart';
import 'offline_service.dart';

class SyncService {
  static SupabaseClient get _db => Supabase.instance.client;

  // ─── Inspection Logs ────────────────────────────────────────────────────────

  /// Drains one queue entry end to end. The single owner of the per-item
  /// protocol — [syncPendingInspections] and [syncSingleInspection] both
  /// delegate here, so the ordering below can never again be fixed in the
  /// bulk path and silently missed in the per-item retry path (or vice
  /// versa).
  ///
  ///  1. legacy-id patch
  ///  2. upsert to Postgres — idempotent.
  ///  3. delete the queue entry ONLY after the database write succeeded.
  ///
  /// Returns true when the entry fully synced and left the queue. Throws
  /// are left to the callers, whose failure handling differs.
  static Future<bool> _syncQueueEntry(
      Box<String> box, dynamic key, String jsonString) async {
    final Map<String, dynamic> data = jsonDecode(jsonString);

    // Patch old invalid UUID format
    if (data['id'] != null && data['id'].toString().contains('_')) {
      data['id'] = null;
    }

    final log = InspectionLog.fromJson(data);

    await _db.from('inspection_logs').upsert(log.toJson());

    // Delete from local queue ONLY on success
    await box.delete(key);
    return true;
  }

  /// Syncs all pending inspections from the local Hive queue to the database.
  // [REF: OFFLINE_SYNC_QUEUE]
  static Future<bool> syncPendingInspections() async {
    final box = OfflineService.inspectionsQueueBox;
    if (box.isEmpty) return true;

    bool allSuccess = true;
    final Map<dynamic, String> entries = box.toMap();

    for (final entry in entries.entries) {
      try {
        if (!await _syncQueueEntry(box, entry.key, entry.value)) {
          allSuccess = false;
        }
      } catch (e) {
        debugPrint('Failed to sync queue item ${entry.key}: $e');
        allSuccess = false;
        // Do not break; attempt others
      }
    }

    return allSuccess;
  }

  /// Syncs a single pending inspection by Hive [key] to the database.
  // [REF: SYNC_SINGLE_ITEM]
  static Future<bool> syncSingleInspection(String key) async {
    final box = OfflineService.inspectionsQueueBox;
    final jsonString = box.get(key);

    if (jsonString == null) return false;

    try {
      return await _syncQueueEntry(box, key, jsonString);
    } catch (e) {
      debugPrint('Failed to sync single item $key: $e');
      return false;
    }
  }

  // ─── Establishments ─────────────────────────────────────────────────────────
  //
  // Read-only from mobile. The web admin owns establishment data, so there is
  // deliberately no insert/update/delete and no outbound establishment queue
  // here — `establishments` is only ever pulled down, by
  // OfflineService.syncData. The RLS policy still permits writes because the
  // web admin needs it (decision D17); mobile not writing is enforced by the
  // absence of a call, not by the policy.

  // ─── Inspection History ──────────────────────────────────────────────────────

  /// Every server log for one establishment, newest first. The caller merges
  /// the local queue.
  static Future<List<Map<String, dynamic>>> fetchLogsForEstablishment(String establishmentId) async {
    final List<dynamic> rows = await _db
        .from('inspection_logs')
        .select()
        .eq('establishment_id', establishmentId)
        .order('inspection_date', ascending: false);
    return rows.cast<Map<String, dynamic>>();
  }

  /// Fetches inspection logs, ordered newest first.
  /// Resolves establishment names by:
  ///   1. Using the name already stored on the log row (fast path).
  ///   2. Looking up the local Hive cache (offline-capable).
  ///   3. Fetching the name DIRECTLY from the `establishments` table
  ///      for any phone with an empty Hive cache (guaranteed resolution).
  /// Also backfills resolved names back to old log rows so every phone
  /// benefits going forward (one-time self-healing per device).
  // [REF: INSPECTION_HISTORY_FETCH]
  static Future<List<Map<String, dynamic>>> fetchInspectionHistory({
    int limit = 50,
  }) async {
    try {
      final List<dynamic> rows = await _db
          .from('inspection_logs')
          .select()
          .order('inspection_date', ascending: false)
          .limit(limit);

      final logs = rows.map((row) {
        final data = Map<String, dynamic>.from(row as Map);
        data['_doc_id'] = data['id'];
        return data;
      }).toList();

      // --- Step 1: quick pass using already-saved names & Hive cache ---
      final List<Map<String, dynamic>> toBackfill = [];
      final Set<String> missingEstIds = {};

      final partiallyEnriched = logs.map((log) {
        final result = Map<String, dynamic>.from(log);

        // Already saved on the row — fastest path, no lookup needed.
        final savedName = log['establishment_name'] as String?;
        if (savedName != null && savedName.isNotEmpty) return result;

        final estId = log['establishment_id'] as String?;
        if (estId == null) {
          result['establishment_name'] = 'Unknown Establishment';
          return result;
        }

        // Try local Hive cache.
        final est = OfflineService.getEstablishmentById(estId);
        final resolvedName = est?.name;
        if (resolvedName != null && resolvedName.isNotEmpty) {
          result['establishment_name'] = resolvedName;
          toBackfill.add({'doc_id': log['_doc_id'], 'name': resolvedName});
        } else {
          // Mark for a server lookup — phone has no local cache.
          result['establishment_name'] = '__PENDING__';
          missingEstIds.add(estId);
        }
        return result;
      }).toList();

      // --- Step 2: server fallback for phones with empty Hive cache ---
      // One `in` filter — the Firestore whereIn 10-id chunking is gone.
      if (missingEstIds.isNotEmpty) {
        final Map<String, String> idToName = {};
        try {
          final List<dynamic> estRows = await _db
              .from('establishments')
              .select('id, business_name')
              .inFilter('id', missingEstIds.toList())
              .timeout(const Duration(seconds: 8));
          for (final row in estRows) {
            final name = row['business_name'] as String?;
            if (name != null && name.isNotEmpty) {
              idToName[row['id'] as String] = name;
            }
          }
        } catch (e) {
          debugPrint('Establishment lookup failed: $e');
        }

        // Fill in the PENDING placeholders with fetched names.
        for (final log in partiallyEnriched) {
          if (log['establishment_name'] == '__PENDING__') {
            final estId = log['establishment_id'] as String?;
            final fetchedName = estId != null ? idToName[estId] : null;
            final resolved = fetchedName ?? 'Unknown Establishment';
            log['establishment_name'] = resolved;
            if (fetchedName != null) {
              toBackfill.add({'doc_id': log['_doc_id'], 'name': fetchedName});
            }
          }
        }
      }

      // --- Step 3: Backfill resolved names to the server (background) ---
      if (toBackfill.isNotEmpty) {
        _backfillEstablishmentNames(toBackfill);
      }

      return partiallyEnriched;
    } catch (e) {
      debugPrint('Fetch inspection history failed: $e');
      rethrow;
    }
  }

  /// Writes resolved establishment names back to old inspection_logs rows.
  /// Called in the background — failures are non-fatal.
  ///
  /// UPDATE, never upsert, matching the Firestore batch.update() this
  /// replaces: an upsert would re-INSERT a log an admin deleted between the
  /// history fetch and this background write, resurrecting it as a skeleton
  /// row (null inspector, null score). An update on a missing id is simply
  /// a no-op. At most ~50 rows per fetch, so per-row requests are fine.
  // [REF: ESTABLISHMENT_NAME_BACKFILL]
  static void _backfillEstablishmentNames(
      List<Map<String, dynamic>> items) async {
    try {
      var updated = 0;
      for (final item in items) {
        final docId = item['doc_id'] as String?;
        final name = item['name'] as String?;
        if (docId == null || name == null) continue;
        await _db
            .from('inspection_logs')
            .update({'establishment_name': name})
            .eq('id', docId)
            .timeout(const Duration(seconds: 10));
        updated++;
      }
      debugPrint(
          'Backfilled establishment_name for $updated inspection log(s).');
    } catch (e) {
      debugPrint('Backfill establishment names failed (non-fatal): $e');
    }
  }

  // ─── Inspection Details ──────────────────────────────────────────────────────

  /// Fetches complete inspection details. The per-item answers live in the
  /// `results` jsonb array on the row (the legacy sub-collection was folded
  /// into it during the Supabase migration).
  // [REF: INSPECTION_DETAILS_FETCH]
  static Future<Map<String, dynamic>> fetchInspectionDetails(
      String logId) async {
    try {
      final row = await _db
          .from('inspection_logs')
          .select()
          .eq('id', logId)
          .maybeSingle();

      if (row == null) {
        throw Exception('Inspection log $logId not found.');
      }

      return Map<String, dynamic>.from(row);
    } catch (e) {
      debugPrint('Fetch inspection details failed: $e');
      rethrow;
    }
  }
}
