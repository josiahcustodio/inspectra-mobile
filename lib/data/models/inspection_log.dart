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
  /// [toQueueJson] but NEVER into the database by [toJson], since a file path on
  /// one inspector's phone is meaningless to anyone else. SyncService uploads
  /// the file from this path on the next successful sync and fills in
  /// [photoEvidenceUrl].
  final String? localPhotoPath;

  // [REF: OFFLINE_SIGNATURE_STAGING]
  /// The inspector's sign-off, captured at submit (Chunk 7).
  ///
  /// [signatureUrl] and [signatureSha256] travel to the database strictly as a
  /// pair — the hash exists to pin the uploaded PNG to this record, so a hash
  /// for an image the server cannot see verifies nothing and [toJson] refuses
  /// to write one. [localSignaturePath] is the same local-only staging idea
  /// as [localPhotoPath]: written to the Hive queue by [toQueueJson] (with
  /// the hash, so the retry can re-pair them), never to the database. All three
  /// nullable because the fields are additive — logs written before Chunk 7
  /// have none of them.
  final String? signatureUrl;
  final String? signatureSha256;
  final String? localSignaturePath;

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
    this.signatureUrl,
    this.signatureSha256,
    this.localSignaturePath,
    List<Map<String, dynamic>>? results,
  })  : id = (id == null || id.isEmpty) ? const Uuid().v4() : id,
        // toUtc(), not local time: inspection_date is a timestamptz column
        // now, and Dart's local toIso8601String carries no UTC offset — the
        // server would misread it as UTC and shift every Manila timestamp
        // by 8 hours.
        inspectionDate =
            inspectionDate ?? DateTime.now().toUtc().toIso8601String(),
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
      signatureUrl: json['signature_url'] as String?,
      signatureSha256: json['signature_sha256'] as String?,
      localSignaturePath: json['local_signature_path'] as String?,
      results: (json['results'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
    );
  }

  /// Matches a trailing UTC 'Z' or a ±HH:MM / ±HHMM offset on an ISO string.
  static final RegExp _hasUtcOffset = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

  /// Normalizes an ISO timestamp for the timestamptz column: a string with
  /// no offset came from a pre-migration build's DateTime.now() (device
  /// LOCAL wall-clock — Hive queue entries written before the update still
  /// carry these), and the server would misread it as UTC, landing Manila
  /// inspections 8 hours early. Dart parses an offset-less string as local
  /// time, so parse → toUtc() recovers the real instant. Applied at the
  /// serialization boundary so EVERY write path inherits the rule, not just
  /// the constructor default.
  static String _normalizeTimestamp(String value) {
    if (_hasUtcOffset.hasMatch(value)) return value;
    try {
      return DateTime.parse(value).toUtc().toIso8601String();
    } catch (_) {
      return value; // unparseable — let the server reject it loudly
    }
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
      'inspection_date': _normalizeTimestamp(inspectionDate),
      'photo_evidence_url': photoEvidenceUrl,
      // Strictly as a pair, in both directions: a hash without an image
      // the server can see verifies nothing, and a URL without its hash loses
      // the tamper-evidence that justifies storing either — any consumer
      // checking one key may assume the other. A still-staged signature
      // keeps its hash in the queue via toQueueJson instead; every live URL
      // acquisition computes the hash first, so withholding an unhashed URL
      // is defensive structure, not a reachable state.
      if (signatureUrl != null && signatureSha256 != null) ...{
        'signature_url': signatureUrl,
        'signature_sha256': signatureSha256,
      },
      'results': results,
    };
  }

  // [REF: OFFLINE_PHOTO_STAGING]
  /// The offline-queue representation. Identical to [toJson] plus the staged
  /// local paths, so a queued inspection remembers which files on this device
  /// still need uploading. Only ever written to Hive, never the database.
  Map<String, dynamic> toQueueJson() {
    final json = toJson();
    if (localPhotoPath != null && localPhotoPath!.isNotEmpty) {
      json['local_photo_path'] = localPhotoPath;
    }
    if (localSignaturePath != null && localSignaturePath!.isNotEmpty) {
      json['local_signature_path'] = localSignaturePath;
      // The hash rides with the staged path even though toJson withheld it
      // (no URL yet): it was computed from the exact bytes in that file, and
      // the retry in SyncService re-pairs it with the URL it earns. Dropping
      // it here would mean re-hashing on retry — hashing a file that could by
      // then differ from what the inspector saw at submit.
      if (signatureSha256 != null) {
        json['signature_sha256'] = signatureSha256;
      }
    }
    return json;
  }
}
