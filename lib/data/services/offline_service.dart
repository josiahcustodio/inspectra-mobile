import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/checklist_template.dart';
import '../models/establishment.dart';

class OfflineService {
  static const String establishmentsBoxName = 'establishments';
  static const String templatesBoxName = 'checklist_templates';
  static const String inspectionsQueueBoxName = 'inspections_queue';

  static Box<String> get inspectionsQueueBox =>
      Hive.box<String>(inspectionsQueueBoxName);

  static Future<void> init() async {
    Hive.registerAdapter(EstablishmentAdapter());
    Hive.registerAdapter(ChecklistTemplateAdapter());

    await Hive.openBox<Establishment>(establishmentsBoxName);
    await Hive.openBox<ChecklistTemplate>(templatesBoxName);
    await Hive.openBox<String>(inspectionsQueueBoxName);
  }

  static Future<void> syncData() async {
    final client = Supabase.instance.client;

    try {
      // ── 1. Fetch categories lookup map: { id -> name } ──────────────────
      final categoriesData = await client.from('categories').select('id, name');
      final Map<int, String> categoryMap = {
        for (final row in categoriesData as List)
          (row['id'] as int): row['name'] as String
      };

      // ── 2. Sync establishments ────────────────────────────────────────────
      final establishmentsData = await client.from('establishments').select();
      final estBox = Hive.box<Establishment>(establishmentsBoxName);
      await estBox.clear();
      for (var json in establishmentsData as List) {
        final enriched = Map<String, dynamic>.from(json);
        final catId = enriched['category_id'];
        if (catId != null) {
          final parsedId = int.tryParse(catId.toString());
          enriched['category_name'] = categoryMap[parsedId] ?? 'Unknown';
        }
        final est = Establishment.fromJson(enriched);
        await estBox.put(est.id, est);
      }

      // ── 3. Sync checklist templates ───────────────────────────────────────
      final templatesData = await client.from('checklist_templates').select();
      final tempBox = Hive.box<ChecklistTemplate>(templatesBoxName);
      await tempBox.clear();
      for (var json in templatesData as List) {
        final enriched = Map<String, dynamic>.from(json);
        final catId = enriched['category_id'];
        if (catId != null) {
          final parsedId = int.tryParse(catId.toString());
          final finalName = categoryMap[parsedId] ?? 'Unknown';
          // Force match the establishment category formatting
          enriched['category_name'] = finalName;
          enriched['category'] = finalName; // add explicitly so Hive object binds correctly
        }
        final template = ChecklistTemplate.fromJson(enriched);
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

  static List<ChecklistTemplate> getLocalTemplatesByCategory(String category) {
    return Hive.box<ChecklistTemplate>(templatesBoxName)
        .values
        .where((t) => t.category.toLowerCase().trim() == category.toLowerCase().trim()) // Relax matching rules
        .toList();
  }
}
