import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../models/checklist_template.dart';
import '../models/inspection_log.dart';
import '../models/establishment.dart';
import 'offline_service.dart';

class SyncService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static FirebaseStorage get _storage => FirebaseStorage.instance;

  // ─── Storage ────────────────────────────────────────────────────────────────

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

  /// Uploads raw [bytes] to Firebase Storage at [path] and returns its public URL.
  static Future<String?> uploadBytes(Uint8List bytes, String path) async {
    try {
      final ref = _storage.ref().child(path);
      await ref.putData(bytes);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Upload bytes failed: $e');
      return null;
    }
  }

  // ─── Inspection Logs ────────────────────────────────────────────────────────

  /// Submits a single [InspectionLog] to Firestore.
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

  /// Inserts an [Establishment] into Firestore.
  /// Returns the new Firestore-generated document ID on success, or null on failure.
  /// The category name is stored directly (denormalized schema).
  static Future<String?> insertEstablishment(Establishment establishment) async {
    try {
      final payload = establishment.toJson();
      final docRef = _db.collection('establishments').doc(establishment.id);
      await docRef.set(payload);
      return docRef.id;
    } catch (e) {
      debugPrint('Establishment insert failed: $e');
      return null;
    }
  }

  /// Updates an [Establishment] in Firestore.
  static Future<bool> updateEstablishment(Establishment establishment) async {
    try {
      final payload = establishment.toJson();
      // merge: true, matching syncPendingEstablishments — a mobile-side edit
      // must never blank fields (e.g. category_id) the web admin app already
      // set, since toJson() omits nulls rather than writing them.
      await _db
          .collection('establishments')
          .doc(establishment.id)
          .set(payload, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('Establishment update failed: $e');
      return false;
    }
  }

  /// Deletes an [Establishment] from Firestore.
  static Future<bool> deleteEstablishment(String id) async {
    try {
      await _db.collection('establishments').doc(id).delete();
      return true;
    } catch (e) {
      debugPrint('Establishment deletion failed: $e');
      return false;
    }
  }

  // Removed submitInspectionResults since results are embedded.

  /// Syncs all unsynced establishments from local Hive to Firestore.
  static Future<bool> syncPendingEstablishments() async {
    final localEstablishments = OfflineService.getLocalEstablishments();
    final pendingEsts = localEstablishments.where((e) => !e.isSynced).toList();

    if (pendingEsts.isEmpty) return true;

    bool allSuccess = true;

    for (var est in pendingEsts) {
      try {
        final payload = est.toJson();
        // Force is_synced to 1 in the remote payload regardless of local state
        payload['is_synced'] = 1;
        
        await _db
            .collection('establishments')
            .doc(est.id)
            .set(payload, SetOptions(merge: true));

        // Update local state to synced
        est.isSynced = true;
        await OfflineService.updateEstablishment(est);
      } catch (e) {
        debugPrint('Failed to sync establishment ${est.id}: $e');
        allSuccess = false;
      }
    }

    return allSuccess;
  }

  // ─── Categories ─────────────────────────────────────────────────────────────

  /// Fetches categories from Firestore as {id, name} pairs. `id` is the
  /// actual `categories/{id}` Firestore doc id and must be used verbatim as
  /// `category_id` when writing establishments — it is not a sequential
  /// index.
  static Future<List<Map<String, String>>> fetchCategories() async {
    try {
      final snapshot = await _db.collection('categories').get();
      final seenNames = <String>{};
      final result = <Map<String, String>>[];
      for (final doc in snapshot.docs) {
        final name = doc.data()['name']?.toString() ?? '';
        if (name.isEmpty || !seenNames.add(name)) continue;
        result.add({'id': doc.id, 'name': name});
      }
      return result;
    } catch (e) {
      debugPrint('Fetch categories failed: $e');
      return const [
        {'id': '1', 'name': 'Food'},
        {'id': '2', 'name': 'Water'},
        {'id': '3', 'name': 'Institutional'},
        {'id': '4', 'name': 'Others'},
      ];
    }
  }

  // ─── Inspection History ──────────────────────────────────────────────────────

  /// Fetches inspection logs from Firestore, ordered newest first.
  /// Returns a list of maps with an extra 'establishment_name' key merged in.
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
        return data;
      }).toList();

      // Enrich with establishment names using the local Hive cache for speed.
      return logs.map((log) {
        final enriched = Map<String, dynamic>.from(log);
        final estId = log['establishment_id'] as String?;
        if (estId != null) {
          final est = OfflineService.getEstablishmentById(estId);
          enriched['establishment_name'] = est?.name ?? 'Unknown Establishment';
        } else {
          enriched['establishment_name'] = 'Unknown Establishment';
        }
        return enriched;
      }).toList();
    } catch (e) {
      debugPrint('Fetch inspection history failed: $e');
      rethrow;
    }
  }

  // ─── Inspection Details ──────────────────────────────────────────────────────

  /// Fetches complete inspection details.
  /// Firestore does not support joins, so inspection_results are stored as
  /// a sub-collection or embedded array in the inspection_log document.
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
