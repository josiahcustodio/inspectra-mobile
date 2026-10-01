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

  // [REF: OFFLINE_CACHE_INIT]
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
  // [REF: MASTER_DATA_SYNC]
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

      // Parse the whole snapshot before touching the box. fromJson casts
      // `personnel_count`, `sanitary_permit_no` and friends, so a single
      // type-drifted document throws — and a throw *after* a clear() would
      // leave the device with an empty box while the catch below reports that
      // it is "relying on local cache".
      final serverEsts = <Establishment>[];
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

        // Forced, not inferred, and load-bearing rather than defensive.
        // Server docs really can carry `is_synced`: the old mobile toJson
        // emitted it, syncPendingEstablishments set it to 1 explicitly, and a
        // row migrated from Supabase can hold 0. fromJson reads any present
        // value, so without this a server record could deserialize as
        // !isSynced, and the bridge below would mistake it for a local-only
        // one and resurrect it on every launch after an admin deleted it.
        data['is_synced'] = true;

        serverEsts.add(Establishment.fromJson(data));
      }

      // [REF: ESTABLISHMENT_UPGRADE_BRIDGE]
      // TEMPORARY — delete in Chunk 6, one release after this ships (D19).
      //
      // Mobile no longer creates establishments (D2), so Firestore is the
      // complete set and a straight replace would be safe from here on. But
      // the Hive box outlives the binary: a device upgrading from a build that
      // still had the add screen can hold an establishment the inspector
      // created offline, which that screen promised to sync later. syncData()
      // runs unconditionally at launch, so clearing without this would destroy
      // the only copy of it, silently.
      //
      // Deliberately NOT pushed to Firestore — a mobile write to
      // `establishments` is exactly what D2 removes. Such a record survives
      // local-only, to be recovered by hand from a support session.
      //
      // Known limitation, and a reason this is temporary: an id missing from
      // the snapshot is either never-synced or admin-deleted, and the bridge
      // cannot tell those apart. Forcing is_synced above confines that to
      // records the old add screen really did write locally.
      // Keyed off the box key, not the id. They are the same today — every
      // write to this box has always been put(est.id, est) — but keys are
      // typed dynamic, so a Set<String>.contains on a non-String key would
      // quietly return false and the record would be deleted instead of kept.
      // Comparing like with like removes that from the story.
      final strandedKeys = estBox
          .toMap()
          .entries
          .where((e) => !e.value.isSynced)
          .map((e) => e.key)
          .toSet();
      if (strandedKeys.isNotEmpty) {
        debugPrint(
          'Upgrade bridge: preserving ${strandedKeys.length} local-only '
          'establishment(s) from a pre-Chunk-1 build',
        );
      }

      // Delete by key rather than clear()ing: the records this bridge exists
      // to protect are never removed at all, so no failure between the delete
      // and the repopulate can lose them. (clear() + re-put would also work —
      // Hive re-inits a disposed HiveObject — but it reopens exactly the
      // window the parse-first pass above was written to close.) A stranded
      // key that also exists on the server is left for putAll to overwrite,
      // so the server copy still wins.
      final staleKeys =
          estBox.keys.where((k) => !strandedKeys.contains(k)).toList();
      await estBox.deleteAll(staleKeys);

      // One transaction, so a backend failure rolls the whole repopulate back
      // instead of leaving a partially filled box behind a log line that says
      // the local cache was kept.
      await estBox.putAll({for (final est in serverEsts) est.id: est});

      // ── 3. Sync checklist templates ───────────────────────────────────────
      final templatesSnapshot =
          await db.collection('checklist_templates').get();
      final tempBox = Hive.box<ChecklistTemplate>(templatesBoxName);

      // Parse before clearing, for the same reason as the establishments pass
      // above: fromJson casts, so one type-drifted document used to throw
      // after the box had been emptied, leaving the device with no checklists
      // at all while the catch below reported it was "relying on local cache".
      // An inspection form with zero items is the visible symptom.
      final serverTemplates = <ChecklistTemplate>[];
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

        serverTemplates.add(ChecklistTemplate.fromJson(data));
      }

      await tempBox.clear();
      await tempBox.putAll({for (final t in serverTemplates) t.id: t});

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

  // [REF: CHECKLIST_TEMPLATE_LOOKUP]
  static List<ChecklistTemplate> getLocalTemplatesByCategory(String category) {
    return Hive.box<ChecklistTemplate>(templatesBoxName)
        .values
        .where((t) =>
            t.category.toLowerCase().trim() ==
            category.toLowerCase().trim())
        .toList();
  }
}
