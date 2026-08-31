import 'package:uuid/uuid.dart';

class InspectionLog {
  final String id;
  final String establishmentId;
  final String inspectorName;
  final int totalDemerits;
  final double percentageRating;
  final String? remarks;
  final String inspectionDate;
  final String? photoEvidenceUrl;
  final List<Map<String, dynamic>> results;

  InspectionLog({
    String? id,
    required this.establishmentId,
    required this.inspectorName,
    required this.totalDemerits,
    required this.percentageRating,
    this.remarks,
    String? inspectionDate,
    this.photoEvidenceUrl,
    List<Map<String, dynamic>>? results,
  })  : id = (id == null || id.isEmpty) ? const Uuid().v4() : id,
        inspectionDate = inspectionDate ?? DateTime.now().toIso8601String(),
        results = results ?? const [];

  factory InspectionLog.fromJson(Map<String, dynamic> json) {
    return InspectionLog(
      id: json['id'] as String?,
      establishmentId: json['establishment_id'] as String? ?? '',
      inspectorName: json['inspector_name'] as String? ?? '',
      totalDemerits: json['total_demerits'] as int? ?? 0,
      percentageRating: (json['percentage_rating'] as num?)?.toDouble() ?? 0.0,
      remarks: json['remarks'] as String?,
      inspectionDate: json['inspection_date'] as String?,
      photoEvidenceUrl: json['photo_evidence_url'] as String?,
      results: (json['results'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'establishment_id': establishmentId,
      'inspector_name': inspectorName,
      'total_demerits': totalDemerits,
      'percentage_rating': percentageRating,
      'remarks': remarks,
      'inspection_date': inspectionDate,
      'photo_evidence_url': photoEvidenceUrl,
      'results': results,
    };
  }
}
