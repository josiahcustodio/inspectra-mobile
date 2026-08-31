import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/checklist_template.dart';
import '../models/establishment.dart';

class OfflineService {
  static const String establishmentsBoxName = 'establishments';
  static const String templatesBoxName = 'checklist_templates';
  static const String inspectionsQueueBoxName = 'inspections_queue';
  static const String prefsBoxName = 'app_prefs';

  static Box<String> get inspectionsQueueBox =>
      Hive.box<String>(inspectionsQueueBoxName);

  static Future<void> init() async {
    Hive.registerAdapter(EstablishmentAdapter());
    Hive.registerAdapter(ChecklistTemplateAdapter());

    await Hive.openBox<Establishment>(establishmentsBoxName);
    await Hive.openBox<ChecklistTemplate>(templatesBoxName);
    await Hive.openBox<String>(inspectionsQueueBoxName);
    await Hive.openBox<String>(prefsBoxName);
  }

  // ─── App Preferences ────────────────────────────────────────────────────────

  static Box<String> get _prefsBox => Hive.box<String>(prefsBoxName);

  static String? readPref(String key) => _prefsBox.get(key);

  static Future<void> writePref(String key, String value) async {
    await _prefsBox.put(key, value);
  }

  /// Syncs master data (establishments, templates, categories) from Firestore
  /// into local Hive boxes for offline use.
  static Future<void> syncData() async {
    final db = FirebaseFirestore.instance;

    try {
      // ── 1. Fetch categories lookup map: { docId -> name } ────────────────
      final categoriesSnapshot = await db.collection('categories').get();
      final Map<String, String> categoryMap = {
        for (final doc in categoriesSnapshot.docs)
          doc.id: (doc.data()['name'] as String? ?? 'Unknown')
      };
      
      // Fallback for known Supabase category IDs if they didn't migrate properly
      final defaultCategories = {
        '1': 'Food Establishment',
        '2': 'Water',
        '3': 'Institutional',
      };
      for (final entry in defaultCategories.entries) {
        if (!categoryMap.containsKey(entry.key) && !categoryMap.containsValue(entry.value)) {
          categoryMap[entry.key] = entry.value;
        }
      }

      // ── 2. Sync establishments ────────────────────────────────────────────
      final establishmentsSnapshot =
          await db.collection('establishments').get();
      final estBox = Hive.box<Establishment>(establishmentsBoxName);
      
      // Preserve unsynced establishments so they are not lost
      final unsyncedEsts = estBox.values.where((e) => !e.isSynced).toList();
      
      await estBox.clear();

      for (final doc in establishmentsSnapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;

        // Robust category resolution
        String? catId = data['category_id']?.toString();
        if (catId == null && data['category'] != null) {
          // If category looks like a numeric ID, use it as catId
          if (int.tryParse(data['category'].toString()) != null) {
            catId = data['category'].toString();
          }
        }
        
        if (catId != null && categoryMap.containsKey(catId)) {
          data['category_name'] = categoryMap[catId];
          data['category'] = categoryMap[catId];
        } else if (data['category'] == null || data['category'].toString().isEmpty) {
          data['category'] = 'Unknown';
        }

        final est = Establishment.fromJson(data);
        await estBox.put(est.id, est);
      }
      
      // Restore unsynced establishments
      for (final est in unsyncedEsts) {
        await estBox.put(est.id, est);
      }

      // ── 3. Sync checklist templates ───────────────────────────────────────
      final templatesSnapshot =
          await db.collection('checklist_templates').get();
      final tempBox = Hive.box<ChecklistTemplate>(templatesBoxName);
      await tempBox.clear();

      for (final doc in templatesSnapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;

        // Robust category resolution
        String? catId = data['category_id']?.toString();
        if (catId == null && data['category'] != null) {
          // If category looks like a numeric ID, use it as catId
          if (int.tryParse(data['category'].toString()) != null) {
            catId = data['category'].toString();
          }
        }
        
        if (catId != null && categoryMap.containsKey(catId)) {
          data['category_name'] = categoryMap[catId];
          data['category'] = categoryMap[catId];
        } else if (data['category'] == null || data['category'].toString().isEmpty) {
          data['category'] = 'Unknown';
        }

        final template = ChecklistTemplate.fromJson(data);
        await tempBox.put(template.id, template);
      }

      debugPrint('Synced ${tempBox.length} templates successfully.');
    } catch (e, st) {
      debugPrint('Sync failed, relying on local cache: $e\n$st');
    }
  }

  static List<Establishment> getLocalEstablishments() {
    return Hive.box<Establishment>(establishmentsBoxName).values.toList();
  }

  static Establishment? getEstablishmentById(String id) {
    return Hive.box<Establishment>(establishmentsBoxName).get(id);
  }

  static Future<void> updateEstablishment(Establishment establishment) async {
    await Hive.box<Establishment>(establishmentsBoxName).put(establishment.id, establishment);
  }

  static Future<void> deleteEstablishment(String id) async {
    await Hive.box<Establishment>(establishmentsBoxName).delete(id);
  }

  static List<ChecklistTemplate> getLocalTemplatesByCategory(String category) {
    return Hive.box<ChecklistTemplate>(templatesBoxName)
        .values
        .where((t) =>
            t.category.toLowerCase().trim() ==
            category.toLowerCase().trim())
        .toList();
  }
}
