import 'package:hive/hive.dart';

part 'establishment.g.dart';

@HiveType(typeId: 0)
class Establishment extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String category;

  @HiveField(3)
  final String address;

  @HiveField(4)
  final String ownerName;

  @HiveField(5)
  final int personnelCount;

  @HiveField(6)
  final int personnelWithHc;

  @HiveField(7)
  final String sanitaryPermitNo;

  @HiveField(8)
  final String controlNo;

  Establishment({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    this.ownerName = '',
    this.personnelCount = 0,
    this.personnelWithHc = 0,
    this.sanitaryPermitNo = '',
    this.controlNo = '',
  });

  factory Establishment.fromJson(Map<String, dynamic> json) {
    return Establishment(
      id: json['id']?.toString() ?? '',
      name: json['business_name'] as String? ?? '',
      // category_name is injected by syncData after joining categories table
      category: (json['category_name'] as String?) ??
          (json['category'] as String?) ??
          'Unknown',
      address: json['address'] as String? ?? '',
      ownerName: json['owner_name'] as String? ?? '',
      personnelCount: json['personnel_count'] as int? ?? 0,
      personnelWithHc: json['personnel_with_hc'] as int? ?? 0,
      sanitaryPermitNo: json['sanitary_permit_no'] as String? ?? '',
      controlNo: json['control_no'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'business_name': name,
      'category': category,
      'address': address,
      'owner_name': ownerName,
      'personnel_count': personnelCount,
      'personnel_with_hc': personnelWithHc,
      'sanitary_permit_no': sanitaryPermitNo,
      'control_no': controlNo,
      'created_at': DateTime.now().toIso8601String(),
    };
  }
}
