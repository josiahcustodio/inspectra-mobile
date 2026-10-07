import 'package:hive/hive.dart';

import 'checklist_template.dart';

part 'inspection_category.g.dart';

/// [REF: INSPECTION_CATEGORY_MODEL]
/// One `categories` document — the checklist type an inspection is scored
/// against.
///
/// Cached in Hive rather than fetched on demand because the picker has to work
/// in a dead zone: an inspector standing in a market with no signal still has
/// to be able to open the right checklist. `syncData` writes this box on every
/// launch that has a connection.
@HiveType(typeId: 2)
class InspectionCategory extends HiveObject {
  /// The `categories/{id}` document id, verbatim — `'1'`, `'17'`, not an index.
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  /// The city's intended display order, added to every category in Chunk 2.5.
  ///
  /// Defaulted rather than required because a category seeded without one must
  /// sort last, not first, and 9999 puts it behind the deliberately-parked
  /// `'9'` at 999. Not for box compatibility — typeId 2 is new in this chunk,
  /// so no record predating this field can exist; the `defaultValue` is what
  /// keeps the field safe to leave off a future write, and what stops a
  /// non-nullable int reading back as null if it ever is.
  @HiveField(2, defaultValue: 9999)
  final int sortOrder;

  InspectionCategory({
    required this.id,
    required this.name,
    this.sortOrder = 9999,
  });

  factory InspectionCategory.fromJson(Map<String, dynamic> json) {
    return InspectionCategory(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Unknown',
      // `as num` then toInt: the seeding script writes an int, but a value
      // hand-edited in a console has come back as a double before (Firestore
      // era); the cast tolerates either.
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 9999,
    );
  }
}

// [REF: CATEGORY_AVAILABILITY]
/// Why a category cannot be inspected right now.
///
/// Both cases are *derived*, never hardcoded against a document id. That is the
/// whole point: an id test would state a coincidence, these state the actual
/// reason and stop being true the day the reason stops being true.
enum CategoryUnavailableReason {
  /// No checklist items resolve to this category on this device.
  ///
  /// Two different situations share this value and the app genuinely cannot
  /// tell them apart from here: a category that has never had a checklist
  /// published (live `'9' Food`, deliberately kept for the 14 establishments
  /// still pointing at it), and a category whose templates simply have not
  /// synced to this phone yet. The copy has to cover both.
  noChecklistItems,

  /// Every template in the category has `weight: 0`, so `100 - totalDemerits`
  /// cannot produce a meaningful score (D22/D25).
  ///
  /// Livestock Farm is the live instance: its 13 items were seeded at weight 0
  /// because no demerit weighting has ever been published for that form, and
  /// inventing one would fabricate regulatory data. Submitting it today would
  /// record a flat 100 / Excellent for an inspection nobody scored. The real
  /// fix is a per-category scoring mode in both apps (Chunk 5 territory);
  /// until then the form is withheld, and the rule self-heals the moment a
  /// weighting is published.
  noScoringPublished,
}

/// [REF: CATEGORY_OPTION]
/// One row of the picker: a category, what it resolves to locally, and whether
/// it can be inspected.
///
/// Availability is decided here and nowhere else. The widget renders what this
/// says; it does not count templates or inspect weights for itself, because two
/// places deciding the same thing is how a disabled row ends up submittable.
class CategoryOption {
  final InspectionCategory category;

  /// How many checklist items resolved to this category *on this device*.
  final int templateCount;

  /// `null` when the category can be inspected.
  final CategoryUnavailableReason? unavailableReason;

  const CategoryOption({
    required this.category,
    required this.templateCount,
    this.unavailableReason,
  });

  bool get isSelectable => unavailableReason == null;

  /// Human-readable cause, for the disabled row's own label.
  ///
  /// D25: an unselectable category is shown, visibly disabled, carrying its
  /// reason — never hidden. A missing row is indistinguishable from a failed
  /// sync, and would leave an inspector concluding the app is broken instead of
  /// reporting that a weighting has never been published.
  String? get unavailableLabel => switch (unavailableReason) {
        CategoryUnavailableReason.noChecklistItems =>
          'No checklist items on this device',
        CategoryUnavailableReason.noScoringPublished =>
          'Scoring not yet published for this form',
        null => null,
      };

  /// Derives a row from a category and the templates that resolved to it.
  ///
  /// Pure, and takes a plain list rather than reading Hive, so the rules above
  /// are testable without a box — the same reason `EstablishmentBanner`'s
  /// `densityFor` was made static.
  static CategoryOption evaluate(
    InspectionCategory category,
    List<ChecklistTemplate> templates,
  ) {
    // Order matters: "every weight is zero" is vacuously true of an empty
    // list, so the empty case has to be answered first or a category with no
    // checklist at all would report the wrong reason.
    if (templates.isEmpty) {
      return CategoryOption(
        category: category,
        templateCount: 0,
        unavailableReason: CategoryUnavailableReason.noChecklistItems,
      );
    }

    final scorable = templates.any((t) => t.weight > 0);
    return CategoryOption(
      category: category,
      templateCount: templates.length,
      unavailableReason:
          scorable ? null : CategoryUnavailableReason.noScoringPublished,
    );
  }

  /// Sort order for the picker: the city's `sort_order`, then name, then id.
  ///
  /// The id tiebreak is not decoration — `'1'` and `'9'` are both named `Food`
  /// in the live data, so name alone leaves two rows in an order that could
  /// swap between launches.
  static int compare(CategoryOption a, CategoryOption b) {
    final bySort = a.category.sortOrder.compareTo(b.category.sortOrder);
    if (bySort != 0) return bySort;
    final byName = a.category.name
        .toLowerCase()
        .compareTo(b.category.name.toLowerCase());
    if (byName != 0) return byName;
    return a.category.id.compareTo(b.category.id);
  }
}
