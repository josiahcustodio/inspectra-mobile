import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inspection_log.dart';
import '../models/establishment.dart';
import 'offline_service.dart';

class SyncService {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<String?> uploadImage(File imageFile, String path) async {
    try {
      await client.storage.from('inspection_evidence').upload(path, imageFile);
      final String publicUrl =
          client.storage.from('inspection_evidence').getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      debugPrint('Upload image failed: $e');
      return null;
    }
  }

  static Future<String?> uploadBytes(Uint8List bytes, String path) async {
    try {
      await client.storage
          .from('inspection_evidence')
          .uploadBinary(path, bytes);
      final String publicUrl =
          client.storage.from('inspection_evidence').getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      debugPrint('Upload bytes failed: $e');
      return null;
    }
  }

  static Future<bool> submitInspectionLog(InspectionLog log) async {
    try {
      await client.from('inspection_logs').insert(log.toJson());
      return true;
    } catch (e) {
      debugPrint('Submission failed: $e');
      return false;
    }
  }

  static Future<bool> syncPendingInspections() async {
    final box = OfflineService.inspectionsQueueBox;
    if (box.isEmpty) return true; // Nothing to sync

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

        // Upload idempotent payload
        // Note: The Supabase 'id' column will handle duplicate rejections if properly configured as primary key
        await client.from('inspection_logs').upsert(log.toJson());

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

      await client.from('inspection_logs').upsert(log.toJson());

      // Delete from local queue ONLY on success
      await box.delete(key);
      return true;
    } catch (e) {
      debugPrint('Failed to sync single item $key: $e');
      return false;
    }
  }

  static Future<bool> insertEstablishment(Establishment establishment) async {
    try {
      final payload = establishment.toJson();

      // Look up category_id from category name
      final String? categoryName = payload['category'] as String?;
      if (categoryName != null) {
        final catRes = await client
            .from('categories')
            .select('id')
            .eq('name', categoryName)
            .maybeSingle();

        if (catRes != null) {
          payload['category_id'] = catRes['id'];
        }
      }
      // Remove text field since establishments table only has category_id
      payload.remove('category');

      await client.from('establishments').insert(payload);
      return true;
    } catch (e) {
      debugPrint('Establishment insert failed: $e');
      return false;
    }
  }

  static Future<List<String>> fetchCategories() async {
    try {
      final response = await client.from('categories').select('name');
      return (response as List).map((row) => row['name'].toString()).toList();
    } catch (e) {
      debugPrint('Fetch categories failed: $e');
      return ['Food', 'Water', 'Institutional', 'Others'];
    }
  }

  /// Fetches inspection logs from Supabase, ordered newest first.
  /// Returns a list of maps with an extra 'establishment_name' key merged in.
  static Future<List<Map<String, dynamic>>> fetchInspectionHistory({
    int limit = 50,
  }) async {
    try {
      final response = await client
          .from('inspection_logs')
          .select()
          .order('inspection_date', ascending: false)
          .limit(limit);

      final logs = (response as List).cast<Map<String, dynamic>>();

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
}
