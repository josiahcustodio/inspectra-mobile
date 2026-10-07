import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inspection_log.dart';
import 'offline_service.dart';

class SyncService {
  static SupabaseClient get _db => Supabase.instance.client;

  /// Ten years. The buckets are PRIVATE and stored URLs are signed —
  /// capability URLs, like the Firebase download URLs they replace, whose
  /// whole point is the unguessable token rather than the deadline. A public
  /// bucket would expose every object at a guessable path.
  static const int _signedUrlTtlSeconds = 10 * 365 * 24 * 60 * 60;

  // ─── Storage ────────────────────────────────────────────────────────────────

  /// Builds the Storage location for an evidence photo.
  ///
  /// Shape: bucket `inspection_evidence`, object `{establishmentId}/{ts}.jpg`.
  /// The Firebase path prefix became the bucket name — the storage policies
  /// grant officers insert on this bucket specifically (and NOT update, which
  /// is why evidence uploads go out with upsert: false: every retry is a
  /// fresh timestamped path, never an overwrite).
  static String evidencePath(String establishmentId) =>
      'inspection_evidence/$establishmentId/${DateTime.now().millisecondsSinceEpoch}.jpg';

  /// Builds the Storage location for an inspector's sign-off signature.
  ///
  /// Shape: bucket `signatures`, object `{establishmentId}/{logId}.png`.
  /// Deterministic where [evidencePath] is timestamped, on purpose: a
  /// signature retry should overwrite its own earlier attempt rather than
  /// litter the bucket, and the log row only ever points at one URL anyway.
  /// The storage policies grant officers `update` on this bucket for exactly
  /// this reason, and the upload goes out with upsert: true.
  static String signaturePath(String establishmentId, String logId) =>
      'signatures/$establishmentId/$logId.png';

  /// Splits a `bucket/objectPath` string at the first '/'. The two path
  /// builders above keep the full-path shape the Firebase era used (and the
  /// queue entries on devices in the field were written against), so the
  /// bucket is peeled off here instead of changing the shape everywhere.
  static ({String bucket, String object}) _splitPath(String path) {
    final i = path.indexOf('/');
    return (bucket: path.substring(0, i), object: path.substring(i + 1));
  }

  // [REF: PHOTO_UPLOAD]
  /// Uploads a [File] to Supabase Storage at [path] and returns its public URL.
  ///
  /// [contentType] is required, not inferred: the SDK would otherwise fall
  /// back to a generic type for a plain file path, and the buckets pin their
  /// allowed MIME types (`signatures` exactly image/png, `inspection_evidence`
  /// image/*) — an un-pinned upload can pass a desk test and still fail in
  /// the field. [upsert] must mirror the bucket's policy: signatures may
  /// overwrite themselves, evidence may not.
  static Future<String?> uploadImage(
      File imageFile, String path, String contentType,
      {bool upsert = false}) async {
    try {
      final loc = _splitPath(path);
      final storage = _db.storage.from(loc.bucket);
      await storage.upload(
        loc.object,
        imageFile,
        fileOptions: FileOptions(contentType: contentType, upsert: upsert),
      );
      return await storage.createSignedUrl(loc.object, _signedUrlTtlSeconds);
    } catch (e) {
      debugPrint('Upload image failed: $e');
      return null;
    }
  }

  /// Uploads in-memory PNG bytes to [path] and returns the public URL.
  ///
  /// The signature's disk-failed fallback: used only when the pad's bytes
  /// could not even be staged to a file, where [uploadImage] has nothing to
  /// read. The content type is pinned explicitly because raw bytes carry no
  /// extension to infer it from, and the `signatures` bucket rejects
  /// anything that is not image/png.
  static Future<String?> uploadSignatureBytes(
      Uint8List bytes, String path) async {
    try {
      final loc = _splitPath(path);
      final storage = _db.storage.from(loc.bucket);
      await storage.uploadBinary(
        loc.object,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/png', upsert: true),
      );
      return await storage.createSignedUrl(loc.object, _signedUrlTtlSeconds);
    } catch (e) {
      debugPrint('Upload signature bytes failed: $e');
      return null;
    }
  }

  // [REF: OFFLINE_PHOTO_RETRY]
  /// Uploads an evidence photo that was captured offline and staged on disk.
  ///
  /// Mutates [data] in place: on success it fills in `photo_evidence_url` and
  /// drops `local_photo_path`, so the record written to the database never
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
      // A URL checkpointed by the PRE-MIGRATION build points at Firebase
      // Storage — an object copy_storage.py never saw, doomed to 404 when
      // that project is decommissioned. The staged file is still on disk
      // (this branch only runs with a local path present), so drop the
      // stale URL and fall through to re-upload to Supabase instead.
      if (existingUrl.contains('firebasestorage')) {
        data.remove('photo_evidence_url');
      } else {
        data.remove('local_photo_path');
        return (ready: true, mutated: true);
      }
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
  /// on the next drain, when a failed database write left the checkpointed
  /// entry behind. (The lingering path key never reaches the database:
  /// InspectionLog.toJson has no `local_signature_path` output at all.)
  static Future<({bool ready, bool mutated, File? uploadedStagedFile})>
      _uploadStagedSignature(Map<String, dynamic> data) async {
    final localPath = data['local_signature_path'] as String?;
    final existingUrl = data['signature_url'] as String?;

    if (localPath == null || localPath.isEmpty) {
      return (ready: true, mutated: false, uploadedStagedFile: null);
    }
    if (existingUrl != null &&
        existingUrl.isNotEmpty &&
        !existingUrl.contains('firebasestorage')) {
      // A previous drain uploaded this signature, checkpointed URL + path to
      // the queue, and then failed the database write (or died). The URL is
      // durable in this entry, so the staged copy has served its purpose —
      // delete it here or nothing ever will.
      data.remove('local_signature_path');
      try {
        File(localPath).deleteSync();
      } catch (_) {}
      return (ready: true, mutated: true, uploadedStagedFile: null);
    }
    if (existingUrl != null && existingUrl.contains('firebasestorage')) {
      // Checkpointed by the PRE-MIGRATION build: the object lives only in
      // Firebase Storage and will 404 after decommission, breaking the
      // url/sha256 tamper-evidence pair. The staged PNG is still on disk
      // (deleted only after a non-Firebase URL is durable), so drop the
      // stale URL and re-upload to Supabase below.
      data.remove('signature_url');
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
    final url = await uploadImage(
        file, signaturePath(estId, logId), 'image/png',
        upsert: true);
    if (url == null) {
      // still offline — retry on the next sync
      return (ready: false, mutated: false, uploadedStagedFile: null);
    }

    data['signature_url'] = url;
    return (ready: true, mutated: true, uploadedStagedFile: file);
  }

  // ─── Inspection Logs ────────────────────────────────────────────────────────

  /// Submits a single [InspectionLog] to the database.
  // [REF: INSPECTION_SUBMIT_REMOTE]
  static Future<bool> submitInspectionLog(InspectionLog log) async {
    try {
      await _db.from('inspection_logs').upsert(log.toJson());
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
  ///     it — before any early return and before the database write, so an
  ///     earned URL is durable the moment it exists. Skipped when nothing
  ///     changed: an attachment-less inspection must not pay a disk write
  ///     (and a queue-listener UI rebuild) per drain attempt.
  ///  4. bail out (entry stays queued) if either attachment still needs a
  ///     retry — the record and its evidence leave the queue together or
  ///     not at all.
  ///  5. upsert to Postgres — idempotent, the set(merge:true) equivalent.
  ///  6. delete the queue entry ONLY after the database write succeeded.
  ///  7. only now delete the staged signature PNG: the URL that replaces it
  ///     is durable in the database and nothing references the file. Failing
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
      // that is still pending, and a signature URL survives a database
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
    // has no such output, so it cannot leak into the database.
    final log = InspectionLog.fromJson(data);

    await _db.from('inspection_logs').upsert(log.toJson());

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

      final data = Map<String, dynamic>.from(row);

      // Kept under both keys — the details screen historically read
      // `inspection_results`.
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
