import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

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

  @HiveField(9, defaultValue: '')
  final String barangay;

  // Firestore doc id from the `categories` collection — a string, not a
  // sequential index. Nullable because older synced records may predate
  // this field.
  @HiveField(10)
  final String? categoryId;

  @HiveField(11, defaultValue: true)
  bool isSynced;

  @HiveField(12)
  String? createdAt;

  @HiveField(13)
  final String? qrCodeId;

  Establishment({
    String? id,
    required this.name,
    required this.category,
    required this.address,
    this.ownerName = '',
    this.personnelCount = 0,
    this.personnelWithHc = 0,
    this.sanitaryPermitNo = '',
    this.controlNo = '',
    this.barangay = '',
    this.categoryId,
    this.isSynced = true,
    this.createdAt,
    this.qrCodeId,
  }) : id = (id == null || id.isEmpty) ? const Uuid().v4() : id;

  String get formattedAddress {
    try {
      if (address.trim().startsWith('{')) {
        final map = jsonDecode(address);
        return map['fullAddress'] ?? address;
      }
    } catch (_) {}
    return address;
  }

  factory Establishment.fromJson(Map<String, dynamic> json) {
    dynamic addressData = json['address'];
    String addressStr = 'N/A';
    if (addressData is Map) {
      addressStr = jsonEncode(addressData);
    } else if (addressData is String && addressData.isNotEmpty) {
      addressStr = addressData;
    }

    return Establishment(
      id: json['id']?.toString(),
      name: json['business_name'] as String? ?? '',
      // category_name is injected by syncData after joining categories table
      category: (json['category_name'] as String?) ??
          (json['category'] as String?) ??
          'Unknown',
      address: addressStr,
      ownerName: json['owner_name'] as String? ?? '',
      personnelCount: json['personnel_count'] as int? ?? 0,
      personnelWithHc: json['personnel_with_hc'] as int? ?? 0,
      sanitaryPermitNo: json['sanitary_permit_no'] as String? ?? '',
      controlNo: json['control_no'] as String? ?? '',
      barangay: json['barangay'] as String? ?? '',
      categoryId: json['category_id']?.toString(),
      isSynced: json['is_synced'] == null ? true : (json['is_synced'] == 1 || json['is_synced'] == true),
      createdAt: json['created_at'] as String?,
      qrCodeId: json['qr_code_id'] as String?,
    );
  }

  /// Firestore-bound JSON. [categoryId], [barangay] and [qrCodeId] are only
  /// included when set, so a write from this client never blanks out a value
  /// the web admin app (or a future mobile screen) already stored — this
  /// relies on [SyncService.updateEstablishment] using `SetOptions(merge: true)`.
  Map<String, dynamic> toJson() {
    dynamic addressPayload = address;
    if (address.trim().startsWith('{') && address.trim().endsWith('}')) {
      try {
        addressPayload = jsonDecode(address);
      } catch (_) {}
    }

    final json = <String, dynamic>{
      'business_name': name,
      'category': category,
      'address': addressPayload,
      'owner_name': ownerName,
      if (barangay != null) 'barangay': barangay,
      'personnel_count': personnelCount,
      'personnel_with_hc': personnelWithHc,
      'sanitary_permit_no': sanitaryPermitNo,
      'control_no': controlNo,
      'is_synced': isSynced ? 1 : 0,
      'created_at': createdAt ?? DateTime.now().toIso8601String(),
      if (qrCodeId != null) 'qr_code_id': qrCodeId,
    };
    // Omit rather than write null/empty — this doc is written with
    // SetOptions(merge: true), so an omitted key leaves whatever the other
    // client (web) already set untouched, instead of blanking it out.
    if (barangay.isNotEmpty) json['barangay'] = barangay;
    if (categoryId != null) json['category_id'] = categoryId;
    return json;
  }
}
