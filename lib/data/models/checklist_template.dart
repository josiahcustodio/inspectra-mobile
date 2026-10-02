import 'package:hive/hive.dart';

part 'checklist_template.g.dart';

@HiveType(typeId: 1)
class ChecklistTemplate extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String category;

  @HiveField(2)
  final String subCategory;

  @HiveField(3)
  final String item;

  @HiveField(4)
  final int weight;

  /// The `categories/{id}` document id this item belongs to — the machine key
  /// the inspection form resolves a checklist by (D24).
  ///
  /// Nullable because it has to be, not as a style choice: this box already
  /// ships on inspectors' phones holding records written before field 5
  /// existed. Hive hands a missing field back as `null`, so a non-nullable
  /// `fields[5] as String` would throw on every read of an un-upgraded box and
  /// leave the device with no checklists at all. See
  /// [REF: TEMPLATE_LOOKUP_ID_BRIDGE] in OfflineService for how the lookup
  /// copes for the one release that matters.
  @HiveField(5)
  final String? categoryId;

  ChecklistTemplate({
    required this.id,
    required this.category,
    required this.subCategory,
    required this.item,
    required this.weight,
    this.categoryId,
  });

  factory ChecklistTemplate.fromJson(Map<String, dynamic> json) {
    return ChecklistTemplate(
      id: json['id']?.toString() ?? '',
      // category_name is injected by syncData after joining categories table
      category: (json['category_name'] as String?) ??
          (json['category'] as String?) ??
          'Unknown',
      subCategory: json['sub_category'] as String? ?? 'General',
      item: json['item_name'] as String? ?? json['item'] as String? ?? '',
      weight: (json['weight'] as num?)?.toInt() ?? 5,
      // Coerced rather than cast. Every template doc in Firestore carries a
      // string today, but `category_id` has drifted to a raw number before now
      // (three establishments still hold the int 1), and syncData already
      // defends against it the same way.
      categoryId: json['category_id']?.toString(),
    );
  }

  /// Creates a minimal placeholder used when a template ID in notes
  /// no longer matches any loaded template. This prevents a [StateError]
  /// crash from [List.firstWhere] in inspection submission logic.
  factory ChecklistTemplate.empty(String id) {
    return ChecklistTemplate(
      id: id,
      category: '',
      subCategory: '',
      item: id, // Fall back to showing the raw ID in the remarks string
      weight: 0,
    );
  }
}
