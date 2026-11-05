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

  // Field numbers are permanent: they are already in every inspector's Hive
  // box, and one that stops being declared can never be safely reused.
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

  // The id from the `categories` table — a string, not a
  // sequential index. Nullable because older synced records may predate
  // this field.
  @HiveField(10)
  final String? categoryId;

  // Vestigial for new records — mobile no longer creates establishments, so
  // nothing sets this false any more. Still read in exactly one place:
  // [REF: ESTABLISHMENT_UPGRADE_BRIDGE] in offline_service.syncData, which
  // uses it to spot records an older build created offline. That branch and
  // this comment both go in Chunk 6; the field itself stays, for the same
  // box-compatibility reason as fields 5–9.
  @HiveField(11, defaultValue: true)
  bool isSynced;

  @HiveField(12)
  String? createdAt;

  @HiveField(13)
  final String? qrCodeId;

  // [REF: ESTABLISHMENT_MASTERLIST_FIELDS]
  // Reference copies of the masterlist columns, shown on the inspection form
  // so the inspector can verify they are at the right business. Nullable
  // because records already in a Hive box lack them until the next sync.
  @HiveField(14)
  final String? businessPermitNo;

  @HiveField(15)
  final String? applicType;

  @HiveField(16)
  final String? permitDateIssued;

  @HiveField(17)
  final String? lineOfBusiness;

  @HiveField(18)
  final String? floorAreaSqm;

  @HiveField(19)
  final String? telNo;

  @HiveField(20)
  final String? tin;

  // [REF: ESTABLISHMENT_COORDINATES]
  // Set by the web admin (or a seed); null for every record without a pin.
  // Read only by the field map (ui/screens/map_screen.dart).
  @HiveField(21)
  final double? latitude;

  @HiveField(22)
  final double? longitude;

  bool get hasLocation => latitude != null && longitude != null;

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
    this.businessPermitNo,
    this.applicType,
    this.permitDateIssued,
    this.lineOfBusiness,
    this.floorAreaSqm,
    this.telNo,
    this.tin,
    this.latitude,
    this.longitude,
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

  // [REF: ESTABLISHMENT_FULL_ADDRESS]
  /// The address as an inspector would say it: street, then barangay.
  ///
  /// Masterlist-imported records split the two — the Excel's merged "Business
  /// Address" header puts the street in `address` and the barangay in its own
  /// unnamed column — so rendering `address` alone shows half a location.
  /// The barangay is skipped when it is blank or when the street string
  /// already names it (older hand-entered records often repeat it), so
  /// nothing renders twice.
  String get fullAddress {
    final street = formattedAddress.trim();
    final brgy = barangay.trim();

    final hasStreet = street.isNotEmpty && street.toUpperCase() != 'N/A';
    final hasBrgy = brgy.isNotEmpty &&
        !(hasStreet && street.toLowerCase().contains(brgy.toLowerCase()));

    if (hasStreet && hasBrgy) return '$street, $brgy';
    if (hasStreet) return street;
    if (hasBrgy) return brgy;
    return street; // whatever fromJson left there, typically 'N/A'
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
      // toString, not a cast: floor_area_sqm is numeric, and a type surprise in
      // a display-only column must not abort the whole sync.
      businessPermitNo: json['business_permit_no']?.toString(),
      applicType: json['applic_type']?.toString(),
      permitDateIssued: json['permit_date_issued']?.toString(),
      lineOfBusiness: json['line_of_business']?.toString(),
      floorAreaSqm: json['floor_area_sqm']?.toString(),
      telNo: json['tel_no']?.toString(),
      tin: json['tin']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  // There is deliberately no toJson(): the web admin owns establishment data,
  // so this model is only ever deserialized, never written back to the server.
}
