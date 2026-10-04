import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
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

  /// Builds the Storage path for an inspector's sign-off signature.
  ///
  /// Shape: `signatures/{establishmentId}/{logId}.png`. Deterministic where
  /// [evidencePath] is timestamped, on purpose: a signature retry should
  /// overwrite its own earlier attempt rather than litter the bucket, and the
  /// log document only ever points at one URL anyway. storage.rules grants
  /// officers `update` on this prefix for exactly this reason.
  static String signaturePath(String establishmentId, String logId) =>
      'signatures/$establishmentId/$logId.png';

  // [REF: PHOTO_UPLOAD]
  /// Uploads a [File] to Firebase Storage at [path] and returns its public URL.
  ///
  /// [contentType] is required, not inferred: on Android putFile resolves the
  /// type through ContentResolver, which returns null for a plain file path,
  /// and the upload goes out as application/octet-stream — which
  /// storage.rules rejects on both the `signatures/` prefix (exactly
  /// image/png) and `inspection_evidence/` (image/.*). iOS infers the type
  /// from the file extension, which is why an un-pinned upload can pass a
  /// desk test and still fail on every Android device in the field.
  static Future<String?> uploadImage(
      File imageFile, String path, String contentType) async {
    try {
      final ref = _storage.ref().child(path);
      await ref.putFile(imageFile, SettableMetadata(contentType: contentType));
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Upload image failed: $e');
      return null;
    }
  }

  /// Uploads in-memory PNG bytes to [path] and returns the public URL.
  ///
  /// The signature's disk-failed fallback: used only when the pad's bytes
  /// could not even be staged to a file, where [uploadImage] has nothing to
  /// read. The content type is pinned explicitly because putData has no file
  /// extension to infer it from, and storage.rules on `signatures/` rejects
  /// anything that is not image/png.
  static Future<String?> uploadSignatureBytes(
      Uint8List bytes, String path) async {
    try {
      final ref = _storage.ref().child(path);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Upload signature bytes failed: $e');
      return null;
    }
  }

  // [REF: OFFLINE_PHOTO_RETRY]
  /// Uploads an evidence photo that was captured offline and staged on disk.
  ///
  /// Mutates [data] in place: on success it fills in `photo_evidence_url` and
  /// drops `local_photo_path`, so the record written to Firestore never
  /// carries a device-local file path. `mutated` reports whether anything in
  /// [data] changed, because the caller owes every mutation a durable
  /// checkpoint back into the queue — an earned URL that exists only in this
  /// in-memory map is lost the moment a later step throws, and the retry
  /// would pay for the upload a second time, to a fresh timestamped path.
  ///
  /// `ready: false` only when the photo genuinely still needs another
  /// attempt, which keeps the inspection in the queue (and never coincides
  /// with a mutation). If the staged file has been deleted from the device
  /// (cache cleared, OS reclaimed temp space) the photo is unrecoverable, so
  /// this reports ready and lets the inspection sync without it — holding the
  /// whole record hostage to a file that no longer exists would be worse.
  static Future<({bool ready, bool mutated})> _uploadStagedPhoto(
      Map<String, dynamic> data) async {
    final localPath = data['local_photo_path'] as String?;
    final existingUrl = data['photo_evidence_url'] as String?;

    if (localPath == null || localPath.isEmpty) {
      return (ready: true, mutated: false);
    }
    if (existingUrl != null && existingUrl.isNotEmpty) {
      data.remove('local_photo_path');
      return (ready: true, mutated: true);
    }

    final file = File(localPath);
    if (!file.existsSync()) {
      debugPrint('Staged photo missing from device, syncing without it: $localPath');
      data.remove('local_photo_path');
      return (ready: true, mutated: true);
    }

    final estId = data['establishment_id'] as String? ?? 'unknown';
    final url = await uploadImage(file, evidencePath(estId), 'image/jpeg');
    if (url == null) {
      return (ready: false, mutated: false); // still offline — retry next sync
    }

    data['photo_evidence_url'] = url;
    data.remove('local_photo_path');
    return (ready: true, mutated: true);
  }

  // [REF: OFFLINE_SIGNATURE_RETRY]
  /// Uploads a sign-off signature that was captured offline and staged on
  /// disk. Mirrors [_uploadStagedPhoto], including the missing-file
  /// forgiveness: a staged PNG the OS has reclaimed is unrecoverable, and
  /// holding the whole inspection hostage to it would be worse than syncing
  /// the record without its signature.
  ///
  /// One divergence from the photo path: when the file is gone, the staged
  /// hash is removed along with it. The hash exists to pin an uploaded image
  /// to this record; with the image unrecoverable it pins nothing, and
  /// InspectionLog.toJson's pairing rule must never see a hash it could
  /// accidentally write next to a future, different image.
  ///
  /// The other divergence: a successful upload keeps `local_signature_path`
  /// in [data] alongside the new `signature_url`, so the caller's checkpoint
  /// persists BOTH. The invariant: a staged file may only be deleted once
  /// the URL that replaces it is durable in the queue entry. The file is
  /// destroyed along exactly two paths — by [_syncQueueEntry] after the
  /// queue entry itself is deleted, or by the already-has-URL branch below
  /// on the next drain, when a failed Firestore write left the checkpointed
  /// entry behind. (The lingering path key never reaches Firestore:
  /// InspectionLog.toJson has no `local_signature_path` output at all.)
  static Future<({bool ready, bool mutated, File? uploadedStagedFile})>
      _uploadStagedSignature(Map<String, dynamic> data) async {
    final localPath = data['local_signature_path'] as String?;
    final existingUrl = data['signature_url'] as String?;

    if (localPath == null || localPath.isEmpty) {
      return (ready: true, mutated: false, uploadedStagedFile: null);
    }
    if (existingUrl != null && existingUrl.isNotEmpty) {
      // A previous drain uploaded this signature, checkpointed URL + path to
      // the queue, and then failed the Firestore write (or died). The URL is
      // durable in this entry, so the staged copy has served its purpose —
      // delete it here or nothing ever will.
      data.remove('local_signature_path');
      try {
        File(localPath).deleteSync();
      } catch (_) {}
      return (ready: true, mutated: true, uploadedStagedFile: null);
    }

    final file = File(localPath);
    if (!file.existsSync()) {
      debugPrint(
          'Staged signature missing from device, syncing without it: $localPath');
      data.remove('local_signature_path');
      data.remove('signature_sha256');
      return (ready: true, mutated: true, uploadedStagedFile: null);
    }

    // The id is always a real UUID here: the legacy-id patch in
    // _syncQueueEntry only nulls ids from the pre-UUID era, and no log of
    // that era can carry a staged signature.
    final estId = data['establishment_id'] as String? ?? 'unknown';
    final logId = data['id'] as String? ?? 'unknown';
    final url =
        await uploadImage(file, signaturePath(estId, logId), 'image/png');
    if (url == null) {
      // still offline — retry on the next sync
      return (ready: false, mutated: false, uploadedStagedFile: null);
    }

    data['signature_url'] = url;
    return (ready: true, mutated: true, uploadedStagedFile: file);
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

  /// Drains one queue entry end to end. The single owner of the per-item
  /// protocol — [syncPendingInspections] and [syncSingleInspection] both
  /// delegate here, so the ordering below can never again be fixed in the
  /// bulk path and silently missed in the per-item retry path (or vice
  /// versa).
  ///
  /// The order is the contract, not tidiness:
  ///
  ///  1. legacy-id patch
  ///  2. staged photo upload, then staged signature upload
  ///  3. checkpoint the entry back into the queue IF either upload mutated
  ///     it — before any early return and before Firestore, so an earned
  ///     URL is durable the moment it exists. Skipped when nothing changed:
  ///     an attachment-less inspection must not pay a disk write (and a
  ///     queue-listener UI rebuild) per drain attempt.
  ///  4. bail out (entry stays queued) if either attachment still needs a
  ///     retry — the record and its evidence leave the queue together or
  ///     not at all.
  ///  5. Firestore set(merge: true) — idempotent upsert.
  ///  6. delete the queue entry ONLY after Firestore succeeded.
  ///  7. only now delete the staged signature PNG: the URL that replaces it
  ///     is durable in Firestore and nothing references the file. Failing
  ///     to delete costs kilobytes, not correctness, so it is swallowed.
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

    final photo = await _uploadStagedPhoto(data);
    if (!photo.ready) {
      // A not-ready photo never mutated anything, so there is nothing to
      // checkpoint yet and the signature attempt would fail on the same
      // dead network — leave the entry exactly as found.
      debugPrint('Photo for queue item $key still pending upload; retrying later.');
      return false;
    }

    final signature = await _uploadStagedSignature(data);

    if (photo.mutated || signature.mutated) {
      // The uploads above earned URLs (or shed dead keys) that exist
      // nowhere but this in-memory map. Make that durable before anything
      // else can fail: a photo URL checkpointed here survives a signature
      // that is still pending, and a signature URL survives a Firestore
      // write that throws — without this, the next drain would retry from
      // the original JSON and re-upload evidence it already paid for.
      await box.put(key, jsonEncode(data));
    }

    if (!signature.ready) {
      debugPrint(
          'Signature for queue item $key still pending upload; retrying later.');
      return false;
    }

    // local_signature_path may still be in `data` here (kept so the
    // checkpoint above persists it next to its URL); InspectionLog.toJson
    // has no such output, so it cannot leak into Firestore.
    final log = InspectionLog.fromJson(data);

    await _db
        .collection('inspection_logs')
        .doc(log.id)
        .set(log.toJson(), SetOptions(merge: true));

    // Delete from local queue ONLY on success
    await box.delete(key);

    final staged = signature.uploadedStagedFile;
    if (staged != null) {
      try {
        staged.deleteSync();
      } catch (_) {}
    }
    return true;
  }

  /// Syncs all pending inspections from the local Hive queue to Firestore.
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

  /// Syncs a single pending inspection by Hive [key] to Firestore.
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
