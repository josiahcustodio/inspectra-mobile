import 'package:flutter_test/flutter_test.dart';

import 'package:clowtec_inspector/data/models/checklist_template.dart';
import 'package:clowtec_inspector/data/models/inspection_category.dart';
import 'package:clowtec_inspector/data/services/offline_service.dart';

InspectionCategory category(String id, String name, {int sortOrder = 10}) =>
    InspectionCategory(id: id, name: name, sortOrder: sortOrder);

ChecklistTemplate template(
  String id, {
  required String categoryName,
  String? categoryId,
  int weight = 5,
}) =>
    ChecklistTemplate(
      id: id,
      category: categoryName,
      subCategory: 'General',
      item: 'Item $id',
      weight: weight,
      categoryId: categoryId,
    );

/// Tests for the picker's availability rules (D25) and for the one-release
/// template-lookup bridge.
///
/// Both are pure functions over plain lists specifically so they can be tested
/// without opening a Hive box — `CategoryOption.evaluate` decides whether an
/// inspection can be started at all, and `OfflineService.resolveTemplatesFor`
/// decides what gets scored, which makes them the two pieces of Chunk 3 least
/// acceptable to leave unverified.
void main() {
  group('availability (D25)', () {
    test('a category with no local templates cannot be inspected', () {
      final option = CategoryOption.evaluate(category('9', 'Food'), const []);

      expect(option.isSelectable, isFalse);
      expect(option.unavailableReason,
          CategoryUnavailableReason.noChecklistItems);
      expect(option.templateCount, 0);
      expect(option.unavailableLabel, isNotNull);
    });

    test('a category whose every template is weight 0 cannot be inspected', () {
      // Livestock Farm as actually seeded: 13 items, all weight 0, because no
      // demerit weighting has ever been published for that form (D22).
      final livestock = [
        for (var i = 1; i <= 13; i++)
          template('$i', categoryName: 'Livestock Farm', weight: 0),
      ];

      final option =
          CategoryOption.evaluate(category('17', 'Livestock Farm'), livestock);

      expect(option.isSelectable, isFalse);
      expect(option.unavailableReason,
          CategoryUnavailableReason.noScoringPublished);
      expect(option.templateCount, 13);
      // The reason must be distinct from the empty case: "no checklist items"
      // would send the inspector looking for a sync problem that is not there.
      expect(
        option.unavailableLabel,
        isNot(CategoryOption.evaluate(category('9', 'Food'), const [])
            .unavailableLabel),
      );
    });

    test('the rule is about weights, not about which id it is', () {
      // The day a weighting is published for even one item, the category
      // becomes inspectable with no code change. That is the whole reason the
      // rule is phrased this way instead of as `id == '17'`.
      final weighted = [
        template('1', categoryName: 'Livestock Farm', weight: 0),
        template('2', categoryName: 'Livestock Farm', weight: 5),
      ];

      final option =
          CategoryOption.evaluate(category('17', 'Livestock Farm'), weighted);

      expect(option.isSelectable, isTrue);
      expect(option.unavailableReason, isNull);
      expect(option.unavailableLabel, isNull);
    });

    test('an ordinary 20-item demerits form is selectable', () {
      final food = [
        for (var i = 1; i <= 20; i++)
          template('$i', categoryName: 'Food', weight: 5),
      ];

      final option = CategoryOption.evaluate(category('1', 'Food'), food);

      expect(option.isSelectable, isTrue);
      expect(option.templateCount, 20);
    });
  });

  group('picker ordering', () {
    test('sort_order comes first, and a missing one sinks to the bottom', () {
      final rows = [
        CategoryOption(category: category('17', 'Livestock Farm', sortOrder: 100), templateCount: 13),
        CategoryOption(category: category('1', 'Food', sortOrder: 10), templateCount: 20),
        CategoryOption(category: InspectionCategory(id: '99', name: 'Aardvark'), templateCount: 0),
        CategoryOption(category: category('9', 'Food', sortOrder: 999), templateCount: 0),
      ]..sort(CategoryOption.compare);

      expect(rows.map((r) => r.category.id).toList(),
          ['1', '17', '9', '99']);
    });

    test('two categories with the same name order by id, not by chance', () {
      // '1' and '9' are both named Food in the live data.
      final a = CategoryOption(
          category: category('9', 'Food', sortOrder: 10), templateCount: 0);
      final b = CategoryOption(
          category: category('1', 'Food', sortOrder: 10), templateCount: 20);

      expect(CategoryOption.compare(a, b), greaterThan(0));
      expect(CategoryOption.compare(b, a), lessThan(0));
    });
  });

  group('template lookup by id (D24)', () {
    final box = [
      template('t1', categoryName: 'Food', categoryId: '1'),
      template('t2', categoryName: 'Food', categoryId: '1'),
      template('t3', categoryName: 'Port', categoryId: '15'),
    ];

    test('resolves by id', () {
      final found = OfflineService.resolveTemplatesFor(
        category: category('1', 'Food'),
        allTemplates: box,
      );
      expect(found.map((t) => t.id).toList(), ['t1', 't2']);
    });

    test('a second category with the same name gets nothing', () {
      // This is the hazard the move from name to id removes: under name
      // matching, '9' would have returned the real Food checklist, and seeding
      // one item onto '9' would have added an item to it.
      final found = OfflineService.resolveTemplatesFor(
        category: category('9', 'Food', sortOrder: 999),
        allTemplates: box,
      );
      expect(found, isEmpty);
    });

    test('a category that is not cached locally resolves to nothing', () {
      final found = OfflineService.resolveTemplatesFor(
        category: null,
        allTemplates: box,
      );
      expect(found, isEmpty);
    });

    test('a stray null-id template is left out rather than guessed at', () {
      final mixed = [...box, template('t4', categoryName: 'Food')];
      final found = OfflineService.resolveTemplatesFor(
        category: category('1', 'Food'),
        allTemplates: mixed,
      );
      expect(found.map((t) => t.id).toList(), ['t1', 't2']);
    });
  });

  group('[REF: TEMPLATE_LOOKUP_ID_BRIDGE]', () {
    /// A box as cached by a build that predated `categoryId` — the state an
    /// upgrading phone that is offline will actually be in.
    final legacyBox = [
      template('t1', categoryName: 'Food'),
      template('t2', categoryName: 'Food'),
      template('t3', categoryName: 'Port'),
    ];

    test('falls back to the name when NO template in the box carries an id',
        () {
      final found = OfflineService.resolveTemplatesFor(
        category: category('1', 'Food'),
        allTemplates: legacyBox,
      );
      expect(found.map((t) => t.id).toList(), ['t1', 't2']);
    });

    test('name matching ignores case and padding, as the old lookup did', () {
      final found = OfflineService.resolveTemplatesFor(
        category: category('15', '  pOrT  '),
        allTemplates: legacyBox,
      );
      expect(found.map((t) => t.id).toList(), ['t3']);
    });

    test('the decision is per box, not per template', () {
      // One id anywhere in the box means the box has been re-synced, so the
      // name fallback is off for every row — including the rows that still
      // lack an id. A per-template fallback would let an old-format 'Food'
      // template answer for both '1' and '9' at once.
      final partlyUpgraded = [
        ...legacyBox,
        template('t4', categoryName: 'Food', categoryId: '1'),
      ];

      final found = OfflineService.resolveTemplatesFor(
        category: category('1', 'Food'),
        allTemplates: partlyUpgraded,
      );
      expect(found.map((t) => t.id).toList(), ['t4']);
    });

    test('a category whose name never changed stays selectable', () {
      // Why the bridge has to cover the option list and not just the lookup:
      // without it every category counts zero templates and the whole picker
      // goes unselectable. Note the narrow claim — this holds for `Food`
      // because `Food` is what the legacy box calls it. See the renamed case
      // below for what the bridge does NOT recover.
      final option = CategoryOption.evaluate(
        category('1', 'Food'),
        OfflineService.resolveTemplatesFor(
          category: category('1', 'Food'),
          allTemplates: legacyBox,
        ),
      );
      expect(option.isSelectable, isTrue);
      expect(option.templateCount, 2);
    });

    test('a box left STALE across the Chunk 2.5 rename recovers nothing', () {
      // The bridge's one real limit, and note how narrow it is. The shipped
      // binary rewrites every template's `category` from the live categories
      // map on each sync, so a box synced on or after 2026-10-02 already holds
      // the NEW names and the fallback recovers everything. Only a phone
      // dormant since before that date still labels these templates `Water`,
      // and matching the current name against that old string finds nothing.
      //
      // Asserted so the limit is a recorded fact rather than a Chunk 6
      // surprise — but it is the uncommon case, not the representative one.
      final legacyWater = [
        template('w1', categoryName: 'Water'),
        template('w2', categoryName: 'Water'),
      ];

      final found = OfflineService.resolveTemplatesFor(
        category: category('2', 'Supermarkets', sortOrder: 20),
        allTemplates: legacyWater,
      );
      expect(found, isEmpty);

      final option = CategoryOption.evaluate(
        category('2', 'Supermarkets', sortOrder: 20),
        found,
      );
      expect(option.isSelectable, isFalse);
      expect(option.unavailableReason,
          CategoryUnavailableReason.noChecklistItems);
    });

    test('the bridge DOES re-expose the duplicate-Food collision, knowingly',
        () {
      // Documented cost, not an oversight — and the LIKELY state rather than a
      // curiosity, since any box synced after 2026-10-02 carries the current
      // names and so takes the name path wholesale. While the fallback is
      // active the parked '9' Food resolves to '1' Food's checklist, offers a
      // startable row, and a log can be written against `category_id: '9'`
      // with the right 20 items and a correct score behind it.
      //
      // Bounded: one successful sync turns the id path back on, and D20
      // removes '9'. The alternative was an empty picker. Delete this test
      // with the bridge in Chunk 6.
      final found = OfflineService.resolveTemplatesFor(
        category: category('9', 'Food', sortOrder: 999),
        allTemplates: legacyBox,
      );
      expect(found.map((t) => t.id).toList(), ['t1', 't2']);
    });
  });
}
