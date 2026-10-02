import 'package:uuid/uuid.dart';

class InspectionLog {
  final String id;
  final String establishmentId;

  /// The establishment name, saved directly so other phones don't need
  /// a local Hive cache to resolve it. Falls back to 'Unknown' if absent.
  final String? establishmentName;

  /// Which checklist this inspection was scored against, recorded as BOTH the
  /// `categories` document id and the category name (D24).
  ///
  /// Both, because this document is the audit record and is already
  /// deliberately self-describing: every row of [results] denormalizes its
  /// `item_name`, `sub_category` and `weight`, and [establishmentName] is
  /// stored for the same reason. A bare `category_id: '15'` would be the only
  /// identifier on the document a reader could not resolve, and it goes stale
  /// the moment a category is renamed — which Chunk 2.5 just did to two of
  /// them. The name is the human record of which checklist was administered;
  /// the id is the machine key, and the one identity in that collection that
  /// was never wrong (`'2'` was called "Water" while holding the supermarkets
  /// checklist).
  ///
  /// Nullable because the field is additive: logs written before Chunk 3 have
  /// neither, and nothing may invent one for them.
  final String? categoryId;
  final String? categoryName;

  final String inspectorName;
  final int totalDemerits;
  final double percentageRating;
  final String? remarks;
  final String inspectionDate;
  final String? photoEvidenceUrl;

  /// On-device path of an evidence photo that has not been uploaded yet.
  ///
  /// Local-only staging: it is written into the Hive offline queue by
  /// [toQueueJson] but NEVER into Firestore by [toJson], since a file path on
  /// one inspector's phone is meaningless to anyone else. SyncService uploads
  /// the file from this path on the next successful sync and fills in
  /// [photoEvidenceUrl].
  final String? localPhotoPath;

  final List<Map<String, dynamic>> results;

  InspectionLog({
    String? id,
    required this.establishmentId,
    this.establishmentName,
    this.categoryId,
    this.categoryName,
    required this.inspectorName,
    required this.totalDemerits,
    required this.percentageRating,
    this.remarks,
    String? inspectionDate,
    this.photoEvidenceUrl,
    this.localPhotoPath,
    List<Map<String, dynamic>>? results,
  })  : id = (id == null || id.isEmpty) ? const Uuid().v4() : id,
        inspectionDate = inspectionDate ?? DateTime.now().toIso8601String(),
        results = results ?? const [];

  factory InspectionLog.fromJson(Map<String, dynamic> json) {
    return InspectionLog(
      id: json['id'] as String?,
      establishmentId: json['establishment_id'] as String? ?? '',
      establishmentName: json['establishment_name'] as String?,
      categoryId: json['category_id']?.toString(),
      categoryName: json['category_name'] as String?,
      inspectorName: json['inspector_name'] as String? ?? '',
      totalDemerits: json['total_demerits'] as int? ?? 0,
      percentageRating: (json['percentage_rating'] as num?)?.toDouble() ?? 0.0,
      remarks: json['remarks'] as String?,
      inspectionDate: json['inspection_date'] as String?,
      photoEvidenceUrl: json['photo_evidence_url'] as String?,
      localPhotoPath: json['local_photo_path'] as String?,
      results: (json['results'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
    );
  }

  // [REF: INSPECTION_LOG_MODEL_WRITE]
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'establishment_id': establishmentId,
      if (establishmentName != null) 'establishment_name': establishmentName,
      // Omitted rather than written as null when absent, matching
      // establishment_name above: a Chunk-4 reader has to be able to tell a
      // pre-Chunk-3 log (no such key) from one where the picker somehow
      // recorded nothing.
      if (categoryId != null) 'category_id': categoryId,
      if (categoryName != null) 'category_name': categoryName,
      'inspector_name': inspectorName,
      'total_demerits': totalDemerits,
      'percentage_rating': percentageRating,
      'remarks': remarks,
      'inspection_date': inspectionDate,
      'photo_evidence_url': photoEvidenceUrl,
      'results': results,
    };
  }

  // [REF: OFFLINE_PHOTO_STAGING]
  /// The offline-queue representation. Identical to [toJson] plus
  /// [localPhotoPath], so a queued inspection remembers which photo on this
  /// device still needs uploading. Only ever written to Hive, never Firestore.
  Map<String, dynamic> toQueueJson() {
    final json = toJson();
    if (localPhotoPath != null && localPhotoPath!.isNotEmpty) {
      json['local_photo_path'] = localPhotoPath;
    }
    return json;
  }
}
