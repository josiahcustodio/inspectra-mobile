import 'dart:convert';

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

  // [REF: CHECKLIST_FIELDS]
  /// Extra inputs the form asks for on this item, besides Pass/Fail/N/A: the
  /// blanks and Y/N boxes of forms like Livestock Farm ("_____m, Septic
  /// Tank") that a verdict alone cannot record. Stored as the raw JSON text of
  /// the `checklist_templates.fields` column because Hive has no adapter for
  /// a list of maps; nullable for the same reason as [categoryId] — boxes on
  /// phones predate the field.
  @HiveField(6)
  final String? fieldsJson;

  ChecklistTemplate({
    required this.id,
    required this.category,
    required this.subCategory,
    required this.item,
    required this.weight,
    this.categoryId,
    this.fieldsJson,
  });

  List<ChecklistField> get fields {
    final raw = fieldsJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => ChecklistField.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const []; // a malformed row degrades to a plain Pass/Fail item
    }
  }

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
      // Coerced rather than cast. Every template row carries a
      // string today, but `category_id` has drifted to a raw number before now
      // (three establishments still hold the int 1), and syncData already
      // defends against it the same way.
      categoryId: json['category_id']?.toString(),
      fieldsJson: json['fields'] is List ? jsonEncode(json['fields']) : null,
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

/// One extra input on a checklist item. `label` doubles as the key the value
/// is stored under in the log's `results[].values`, so a result row stays
/// self-describing like its `item_name` does.
///
/// `type` is one of: text, number, date, yesno, choice (one of [options]),
/// multi (any of [options]). Anything else renders as text.
class ChecklistField {
  final String label;
  final String type;
  final List<String> options;

  const ChecklistField({
    required this.label,
    this.type = 'text',
    this.options = const [],
  });

  factory ChecklistField.fromJson(Map<String, dynamic> json) => ChecklistField(
        label: json['label']?.toString() ?? '',
        type: json['type']?.toString() ?? 'text',
        options: (json['options'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
}
