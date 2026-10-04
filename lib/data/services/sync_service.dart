import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../models/inspection_log.dart';
import 'offline_service.dart';

class SyncService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static FirebaseStorage get _storage => FirebaseStorage.instance;

  // ─── Storage ────────────────────────────────────────────────────────────────

  /// Builds the Storage path for an evidence photo.
  ///
  /// Shape: `inspection_evidence/{establishmentId}/{timestamp}.jpg`.
  /// The folder prefix matters — storage.rules grants write access to
  /// `inspection_evidence/**` specifically, which would be impossible to
  /// express if photos were dumped in the bucket root as they used to be.
  static String evidencePath(String establishmentId) =>
      'inspection_evidence/$establishmentId/${DateTime.now().millisecondsSinceEpoch}.jpg';

  // [REF: PHOTO_UPLOAD]
  /// Uploads a [File] to Firebase Storage at [path] and returns its public URL.
  static Future<String?> uploadImage(File imageFile, String path) async {
    try {
      final ref = _storage.ref().child(path);
      await ref.putFile(imageFile);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Upload image failed: $e');
      return null;
    }
  }

  // [REF: OFFLINE_PHOTO_RETRY]
  /// Uploads an evidence photo that was captured offline and staged on disk.
  ///
  /// Mutates [data] in place: on success it fills in `photo_evidence_url` and
  /// drops `local_photo_path`, so the record written to Firestore never
  /// carries a device-local file path.
  ///
  /// Returns false only when the photo genuinely still needs another attempt,
  /// which keeps the inspection in the queue. If the staged file has been
  /// deleted from the device (cache cleared, OS reclaimed temp space) the
  /// photo is unrecoverable, so this returns true and lets the inspection sync
  /// without it — holding the whole record hostage to a file that no longer
  /// exists would be worse.
  static Future<bool> _uploadStagedPhoto(Map<String, dynamic> data) async {
    final localPath = data['local_photo_path'] as String?;
    final existingUrl = data['photo_evidence_url'] as String?;

    if (localPath == null || localPath.isEmpty) return true;
    if (existingUrl != null && existingUrl.isNotEmpty) {
      data.remove('local_photo_path');
      return true;
    }

    final file = File(localPath);
    if (!file.existsSync()) {
      debugPrint('Staged photo missing from device, syncing without it: $localPath');
      data.remove('local_photo_path');
      return true;
    }

    final estId = data['establishment_id'] as String? ?? 'unknown';
    final url = await uploadImage(file, evidencePath(estId));
    if (url == null) return false; // still offline — retry on the next sync

    data['photo_evidence_url'] = url;
    data.remove('local_photo_path');
    return true;
  }

  // ─── Inspection Logs ────────────────────────────────────────────────────────

  /// Submits a single [InspectionLog] to Firestore.
  // [REF: INSPECTION_SUBMIT_REMOTE]
  static Future<bool> submitInspectionLog(InspectionLog log) async {
    try {
      await _db
          .collection('inspection_logs')
          .doc(log.id)
          .set(log.toJson());
      return true;
    } catch (e) {
      debugPrint('Submission failed: $e');
      return false;
    }
  }

  /// Syncs all pending inspections from the local Hive queue to Firestore.
  // [REF: OFFLINE_SYNC_QUEUE]
  static Future<bool> syncPendingInspections() async {
    final box = OfflineService.inspectionsQueueBox;
    if (box.isEmpty) return true;

    bool allSuccess = true;
    final Map<dynamic, String> entries = box.toMap();

    for (final entry in entries.entries) {
      final key = entry.key;
      final jsonString = entry.value;

      try {
        final Map<String, dynamic> data = jsonDecode(jsonString);

        // Patch old invalid UUID format
        if (data['id'] != null && data['id'].toString().contains('_')) {
          data['id'] = null;
        }

        // Upload any photo that was captured while offline, before writing the
        // log. If the upload can't happen yet, leave this item queued so both
        // the record and its evidence are retried together.
        final photoReady = await _uploadStagedPhoto(data);
        if (!photoReady) {
          debugPrint('Photo for queue item $key still pending upload; retrying later.');
          allSuccess = false;
          continue;
        }

        final log = InspectionLog.fromJson(data);

        // Use merge: true for idempotent upsert behaviour
        await _db
            .collection('inspection_logs')
            .doc(log.id)
            .set(log.toJson(), SetOptions(merge: true));

        // Delete from local queue ONLY on success
        await box.delete(key);
      } catch (e) {
        debugPrint('Failed to sync queue item $key: $e');
        allSuccess = false;
        // Do not break; attempt others
      }
    }

    return allSuccess;
  }

  /// Syncs a single pending inspection by Hive [key] to Firestore.
  // [REF: SYNC_SINGLE_ITEM]
  static Future<bool> syncSingleInspection(String key) async {
    final box = OfflineService.inspectionsQueueBox;
    final jsonString = box.get(key);

    if (jsonString == null) return false;

    try {
      final Map<String, dynamic> data = jsonDecode(jsonString);

      // Patch old invalid UUID format
      if (data['id'] != null && data['id'].toString().contains('_')) {
        data['id'] = null;
      }

      // Same photo-first ordering as syncPendingInspections.
      final photoReady = await _uploadStagedPhoto(data);
      if (!photoReady) {
        debugPrint('Photo for queue item $key still pending upload; retrying later.');
        return false;
      }

      final log = InspectionLog.fromJson(data);

      await _db
          .collection('inspection_logs')
          .doc(log.id)
          .set(log.toJson(), SetOptions(merge: true));

      // Delete from local queue ONLY on success
      await box.delete(key);
      return true;
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
  // OfflineService.syncData. The Firestore rule still permits writes because
  // the web admin needs it (see firestore.rules); mobile not writing is
  // enforced by the absence of a call, not by the rule.

  // ─── Categories ─────────────────────────────────────────────────────────────
  //
  // There is no category fetch here. `fetchCategories` used to live at this
  // spot, unreferenced since the add screen was deleted in Chunk 1, and Chunk 3
  // did NOT pick it back up: the picker has to work in a dead zone, so it reads
  // the Hive box that OfflineService.syncData fills (see
  // [REF: CATEGORY_PICKER_OPTIONS]) rather than Firestore. Deleted rather than
  // kept, because every claim its doc comment made had expired — its
  // dedupe-by-name was load-bearing only while eight documents shared the name
  // "Food", and its offline fallback hardcoded `Water` and `Institutional`,
  // which Chunk 2.5 established were never the names of those checklists.

  // ─── Inspection History ──────────────────────────────────────────────────────

  /// Fetches inspection logs from Firestore, ordered newest first.
  /// Resolves establishment names by:
  ///   1. Using the name already stored on the log doc (fast path).
  ///   2. Looking up the local Hive cache (offline-capable).
  ///   3. Fetching the name DIRECTLY from Firestore `establishments` collection
  ///      for any phone with an empty Hive cache (guaranteed resolution).
  /// Also backfills resolved names back to old log docs so every phone
  /// benefits going forward (one-time self-healing per device).
  // [REF: INSPECTION_HISTORY_FETCH]
  static Future<List<Map<String, dynamic>>> fetchInspectionHistory({
    int limit = 50,
  }) async {
    try {
      final snapshot = await _db
          .collection('inspection_logs')
          .orderBy('inspection_date', descending: true)
          .limit(limit)
          .get();

      final logs = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        data['_doc_id'] = doc.id;
        return data;
      }).toList();

      // --- Step 1: quick pass using already-saved names & Hive cache ---
      final List<Map<String, dynamic>> toBackfill = [];
      final Set<String> missingEstIds = {};

      final partiallyEnriched = logs.map((log) {
        final result = Map<String, dynamic>.from(log);

        // Already saved in Firestore — fastest path, no lookup needed.
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
          // Mark for Firestore lookup — phone has no local cache.
          result['establishment_name'] = '__PENDING__';
          missingEstIds.add(estId);
        }
        return result;
      }).toList();

      // --- Step 2: Firestore fallback for phones with empty Hive cache ---
      if (missingEstIds.isNotEmpty) {
        // Fetch all missing establishment docs directly from Firestore.
        // We do it in chunks of 10 (Firestore 'whereIn' limit).
        final idList = missingEstIds.toList();
        final Map<String, String> idToName = {};
        for (int i = 0; i < idList.length; i += 10) {
          final chunk = idList.sublist(
              i, i + 10 > idList.length ? idList.length : i + 10);
          try {
            final estSnap = await _db
                .collection('establishments')
                .where(FieldPath.documentId, whereIn: chunk)
                .get()
                .timeout(const Duration(seconds: 8));
            for (final doc in estSnap.docs) {
              final name = doc.data()['business_name'] as String?;
              if (name != null && name.isNotEmpty) {
                idToName[doc.id] = name;
              }
            }
          } catch (e) {
            debugPrint('Firestore establishment lookup failed: $e');
          }
        }

        // Fill in the PENDING placeholders with fetched names.
        for (final log in partiallyEnriched) {
          if (log['establishment_name'] == '__PENDING__') {
            final estId = log['establishment_id'] as String?;
            final fetchedName =
                estId != null ? idToName[estId] : null;
            final resolved =
                fetchedName ?? 'Unknown Establishment';
            log['establishment_name'] = resolved;
            if (fetchedName != null) {
              toBackfill
                  .add({'doc_id': log['_doc_id'], 'name': fetchedName});
            }
          }
        }
      }

      // --- Step 3: Backfill resolved names to Firestore (background) ---
      if (toBackfill.isNotEmpty) {
        _backfillEstablishmentNames(toBackfill);
      }

      return partiallyEnriched;
    } catch (e) {
      debugPrint('Fetch inspection history failed: $e');
      rethrow;
    }
  }

  /// Writes resolved establishment names back to old Firestore inspection_log docs.
  /// Called in the background — failures are non-fatal.
  // [REF: ESTABLISHMENT_NAME_BACKFILL]
  static void _backfillEstablishmentNames(
      List<Map<String, dynamic>> items) async {
    try {
      final batch = _db.batch();
      for (final item in items) {
        final docId = item['doc_id'] as String?;
        final name = item['name'] as String?;
        if (docId == null || name == null) continue;
        batch.update(
          _db.collection('inspection_logs').doc(docId),
          {'establishment_name': name},
        );
      }
      await batch.commit().timeout(const Duration(seconds: 10));
      debugPrint(
          'Backfilled establishment_name for ${items.length} inspection log(s).');
    } catch (e) {
      debugPrint('Backfill establishment names failed (non-fatal): $e');
    }
  }


  // ─── Inspection Details ──────────────────────────────────────────────────────

  /// Fetches complete inspection details.
  /// Firestore does not support joins, so inspection_results are stored as
  /// a sub-collection or embedded array in the inspection_log document.
  // [REF: INSPECTION_DETAILS_FETCH]
  static Future<Map<String, dynamic>> fetchInspectionDetails(
      String logId) async {
    try {
      final doc =
          await _db.collection('inspection_logs').doc(logId).get();

      if (!doc.exists) {
        throw Exception('Inspection log $logId not found.');
      }

      final data = Map<String, dynamic>.from(doc.data()!);
      data['id'] = doc.id;
      
      // Inspection results are now embedded as an array in the document.
      if (data['results'] != null) {
        data['inspection_results'] = data['results'];
      }

      return data;
    } catch (e) {
      debugPrint('Fetch inspection details failed: $e');
      rethrow;
    }
  }
}
