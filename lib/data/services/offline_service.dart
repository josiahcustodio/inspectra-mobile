import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/checklist_template.dart';
import '../models/establishment.dart';
import '../models/inspection_category.dart';

class OfflineService {
  static const String establishmentsBoxName = 'establishments';
  static const String templatesBoxName = 'checklist_templates';
  static const String categoriesBoxName = 'categories';
  static const String inspectionsQueueBoxName = 'inspections_queue';
  static const String prefsBoxName = 'app_prefs';

  static Box<String> get inspectionsQueueBox =>
      Hive.box<String>(inspectionsQueueBoxName);

  // [REF: OFFLINE_CACHE_INIT]
  static Future<void> init() async {
    Hive.registerAdapter(EstablishmentAdapter());
    Hive.registerAdapter(ChecklistTemplateAdapter());
    Hive.registerAdapter(InspectionCategoryAdapter());

    await _openCacheBox<Establishment>(establishmentsBoxName);
    await _openCacheBox<ChecklistTemplate>(templatesBoxName);
    await _openCacheBox<InspectionCategory>(categoriesBoxName);
    await Hive.openBox<String>(inspectionsQueueBoxName);
    await Hive.openBox<String>(prefsBoxName);
  }

  // [REF: CACHE_BOX_SELF_HEAL]
  /// Opens a Firestore-mirror cache box, recreating it from nothing if the
  /// bytes on disk cannot be read.
  ///
  /// The box file outlives the binary, and the adapter is generated from
  /// whatever the model looked like when THAT build shipped — a device
  /// upgrading from an old APK can hold frames whose field numbers carry
  /// different types (found in the field: a 2026-era tablet box stored an int
  /// where field 10 is now `String? categoryId`, and the resulting cast error
  /// escaped `openBox` and killed startup before the first frame). These
  /// three boxes are pure mirrors refilled by [syncData], so deleting an
  /// unreadable one loses nothing a sync cannot restore — including the D19
  /// bridge's stranded records, which were unreadable on this path anyway.
  ///
  /// The inspections queue and prefs boxes are deliberately NOT routed
  /// through this: the queue holds unsynced field work that must never be
  /// auto-deleted, and both are `Box<String>` — no generated adapter, so
  /// schema drift cannot corrupt them in this way.
  static Future<void> _openCacheBox<T>(String name) async {
    try {
      await Hive.openBox<T>(name);
    } catch (e) {
      debugPrint(
          'Cache box "$name" is unreadable (stale schema from an older build?); '
          'recreating it empty. It will refill on the next sync. Error: $e');
      await Hive.deleteBoxFromDisk(name);
      await Hive.openBox<T>(name);
    }
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

      // Parse before touching the box, for the reason the template pass below
      // does: a throw after a clear() would leave the device with an empty
      // picker behind a log line claiming the local cache was kept. (The
      // establishment pass shares the discipline but not the shape — it
      // deleteAll's selected keys rather than clearing, to protect the D19
      // bridge.)
      //
      // Built from the snapshot ALONE — deliberately above the fallback
      // injection that follows. Those three names are stale fabrications now:
      // Chunk 2.5 proved `'2'` was never Water (it held the SUPERMARKETS
      // checklist and is now named that) and `'3'` was never Institutional,
      // and no category has ever been called "Food Establishment". In the
      // throwaway lookup map the worst they can do is mislabel a denormalized
      // display string. Persisted, they would put a row in the picker for a
      // category that does not exist, which resolves to zero templates and
      // reads to the inspector as a missing checklist rather than as a stale
      // fallback. Fixing the map itself is out of scope here — it still
      // affects nothing the picker reads.
      final serverCategories = <InspectionCategory>[];
      for (final doc in categoriesSnapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        serverCategories.add(InspectionCategory.fromJson(data));
      }

      // An EMPTY result is not propagated, and this is the one box where that
      // matters enough to diverge from the template pass. A `get()` served
      // from an evicted offline cache resolves to an empty snapshot rather
      // than throwing, so the parse above succeeds and a clear() would wipe a
      // good picker on a launch with no signal — leaving the inspector with no
      // category to choose and no category to blame. Nothing is lost by
      // keeping the cache instead: a `categories` collection that is genuinely
      // empty makes every checklist unreachable anyway, so there is no reading
      // of an empty snapshot that the old data serves worse.
      //
      // The establishment and template passes below still DO clear on an empty
      // snapshot. That asymmetry is deliberate but not a judgement that they
      // are safe: it is pre-existing behaviour outside this chunk's scope, and
      // worth closing the same way. Its worst case is a filled categories box
      // over an emptied template box, which shows eleven rows every one of
      // which reports no checklist items.
      final catBox = Hive.box<InspectionCategory>(categoriesBoxName);
      if (serverCategories.isNotEmpty) {
        await catBox.clear();
        await catBox.putAll({for (final c in serverCategories) c.id: c});
      } else {
        debugPrint(
          'Categories snapshot was empty; keeping ${catBox.length} cached '
          'category/categories rather than emptying the picker',
        );
      }

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

        // [REF: DELISTED_FILTER]
        // The web admin marks establishments that dropped off the city
        // masterlist with status 'delisted' rather than deleting them — the
        // web repo's models.ts contract keeps the document for its history,
        // but the business is no longer the city's to inspect, so it must not
        // be offered on mobile. Skipping here, before fromJson, keeps it out
        // of the box entirely; a copy cached before it was delisted falls out
        // via the deleteAll below, exactly as an admin-deleted doc would.
        //
        // An allowlist, not `== 'delisted'`, because the status vocabulary is
        // owned by the web repo (models.ts) and nothing pins the two codebases
        // together: when the web admin grows a second terminal status
        // ('closed', 'suspended'), an equality test here would fail OPEN and
        // keep offering that business for inspection — silently, since mobile
        // still compiles and every test still passes. Unknown statuses hide
        // instead. `null` must stay allowed: legacy documents predate the
        // field entirely.
        //
        // A client-side skip and not a Firestore query, deliberately: a
        // `where('status' == 'active')` query would also drop every legacy
        // document written before the field existed — which today is most of
        // them.
        final status = data['status'];
        if (status != null && status != 'active') continue;

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

        // Write the resolved id back, so the id the template is *stored* under
        // is the same one this pass just used to resolve its name. Without
        // this, a doc that carries its id in `category` instead of
        // `category_id` would cache with a name but no id — invisible to the
        // id lookup, and not enough on its own to trip the name bridge either.
        if (catId != null) data['category_id'] = catId;

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

  // ─── Categories ─────────────────────────────────────────────────────────────

  static Box<InspectionCategory> get _categoriesBox =>
      Hive.box<InspectionCategory>(categoriesBoxName);

  // [REF: CATEGORY_PICKER_OPTIONS]
  /// Every locally cached category as a picker row, in the city's own order,
  /// each already marked selectable or not (D25).
  ///
  /// This is the single place the availability rules are applied — the widget
  /// renders the verdict and never recomputes it. The rules themselves are in
  /// `CategoryOption.evaluate`, stated as derived facts about the templates
  /// rather than as a list of blocked ids.
  ///
  /// Nothing is filtered out. An unselectable category still gets a row,
  /// because a vanished row and a failed sync look identical to an inspector.
  /// That includes the deliberately-parked `'9' Food`, which has no templates
  /// of its own and so lands on the no-checklist rule — the plan's Chunk 3
  /// section claims this filtering is unnecessary after the Chunk 2.5 cleanup,
  /// but `'9'` was knowingly left in place, so it is required after all.
  static List<CategoryOption> getLocalCategoryOptions() {
    final templates = Hive.box<ChecklistTemplate>(templatesBoxName).values.toList();
    final options = _categoriesBox.values
        .map((c) => CategoryOption.evaluate(
              c,
              resolveTemplatesFor(category: c, allTemplates: templates),
            ))
        .toList();
    options.sort(CategoryOption.compare);
    return options;
  }

  // [REF: CHECKLIST_TEMPLATE_LOOKUP]
  /// The checklist for one category, resolved by **document id** (D24).
  ///
  /// Replaces a lookup that matched on the category *name*. Name matching is
  /// what made the duplicate `Food` documents dangerous: two categories sharing
  /// a name merged their templates into a single form, so seeding one item onto
  /// `'9'` would have silently added an item to the real Food checklist. It is
  /// also how a category whose name happened to equal an establishment's
  /// free-text `category` string acquired a working form out of nowhere. Id
  /// resolution makes both impossible by construction instead of safe by
  /// accident.
  static List<ChecklistTemplate> getLocalTemplatesByCategoryId(
      String categoryId) {
    return resolveTemplatesFor(
      category: _categoriesBox.get(categoryId),
      allTemplates: Hive.box<ChecklistTemplate>(templatesBoxName).values.toList(),
    );
  }

  // [REF: TEMPLATE_LOOKUP_ID_BRIDGE]
  /// Picks the templates belonging to [category] out of [allTemplates].
  ///
  /// TEMPORARY in part — delete the name fallback in Chunk 6, alongside the
  /// D19 establishment bridge.
  ///
  /// `ChecklistTemplate.categoryId` is new and the Hive box outlives the
  /// binary, so a phone can hold templates cached without it. The window this
  /// covers is narrower than it first looks, and worth stating exactly,
  /// because it is what a Chunk 6 reader will judge the deletion against:
  ///
  ///  * **Not** "upgraded and still offline". That phone has no `categories`
  ///    box either — it is new in this chunk too — so
  ///    [REF: CATEGORY_PICKER_OPTIONS] has nothing to iterate and this
  ///    function is never reached with a non-null category. The picker is
  ///    empty for want of categories, not for want of ids, and the form says
  ///    so in its own words.
  ///  * The real trigger is a **partial sync**: the categories fetch succeeded
  ///    and filled its box, then the establishments loop threw before the
  ///    templates were replaced — reachable, since `Establishment.fromJson`
  ///    casts `personnel_count` and `sanitary_permit_no`, the type drift Chunk
  ///    1 wrote its parse-before-clear pass for.
  ///
  /// How much it recovers depends on when that box was last written, and the
  /// two cases differ sharply:
  ///
  ///  * **Last synced on or after 2026-10-02**, when Chunk 2.5 was applied to
  ///    production — the common case. The shipped binary rewrites each
  ///    template's `category` from the live `categories` map on every sync, so
  ///    such a box already holds all 193 templates under their *current*
  ///    names. Name matching then recovers **every** category. Note the
  ///    consequence: `'9' Food` matches `'1' Food`'s checklist while the
  ///    fallback is active, so it offers a startable row and a log can be
  ///    written against `category_id: '9'`. Bounded by one successful sync,
  ///    and `'9'` goes away with D20.
  ///  * **Dormant since before 2026-10-02.** That box holds 60 templates under
  ///    the old names, so the two Chunk 2.5 renames (`Water`→Supermarkets,
  ///    `Institutional`→Public Places) match nothing and `'11'`–`'17'` are
  ///    absent entirely. Only Food recovers.
  ///
  /// The fallback is decided for the **whole box**, not per template, and that
  /// distinction is the non-obvious part. A per-template fallback would let an
  /// old-format `Food` template match both `'1'` and `'9'` — re-creating by
  /// accident the exact name-collision hazard D24 removes. One box either
  /// predates the field entirely or does not; mixed state only arises mid-sync,
  /// and syncData replaces the box wholesale.
  ///
  /// Shared by the lookup and by the picker's template counting on purpose: if
  /// they disagreed, a category could offer a row and then resolve to nothing,
  /// or be hidden while its checklist was sitting in the box.
  static List<ChecklistTemplate> resolveTemplatesFor({
    required InspectionCategory? category,
    required List<ChecklistTemplate> allTemplates,
  }) {
    if (category == null) return const [];

    final boxCarriesIds =
        allTemplates.any((t) => (t.categoryId ?? '').isNotEmpty);

    if (boxCarriesIds) {
      // A null id in a box that otherwise has them is a stray, not an old
      // record, so it is left out rather than guessed at by name.
      return allTemplates.where((t) => t.categoryId == category.id).toList();
    }

    final name = category.name.toLowerCase().trim();
    if (name.isEmpty) return const [];
    return allTemplates
        .where((t) => t.category.toLowerCase().trim() == name)
        .toList();
  }
}
