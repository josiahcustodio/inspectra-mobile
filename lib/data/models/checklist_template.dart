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

  ChecklistTemplate({
    required this.id,
    required this.category,
    required this.subCategory,
    required this.item,
    required this.weight,
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
    );
  }
}
