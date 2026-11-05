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

  // [REF: UNSCORED_IS_NOT_ZERO]
  /// Null means the inspection was never scored — NOT a score of zero.
  ///
  /// fromJson used to coerce a missing `percentage_rating` to 0.0, which is
  /// the worst available guess: 0% is the bottom of the lowest band, so an
  /// unscored record rendered as a red failing grade nobody ever recorded.
  /// RatingScale.labelOf/colorOf both take `num?` and have always answered
  /// 'Not Scored Yet' for null — the screens were written for this; only the
  /// model stood in the way. The web client keeps the same distinction
  /// (`percentage_rating: number | null` in models.ts), and
  /// EstablishmentHistoryModal carries a comment about exactly this hazard.
  final double? percentageRating;
  final String? remarks;
  final String inspectionDate;
  // [REF: SANITARY_ORDER_FIELDS]
  /// The Sanitary Order (CHO-ESD-FR-04) this inspection issued, if any.
  ///
  /// All nullable and all omitted from [toJson] when absent, like
  /// [establishmentName] above: a spotless inspection issues no order, and a
  /// reader has to be able to tell "no order" from "an order with nothing
  /// recorded". [soIssuedAt] — not [soNo] — is the marker that an order
  /// exists, because the number is typed off CHO's pre-numbered booklet and
  /// is allowed to stay blank until their pattern is known.
  ///
  /// `email_sent_at` is deliberately NOT modelled here. It is stamped by the
  /// delivery function server-side, and [toJson] is upserted on every retry —
  /// a client that carried the field would overwrite the server's stamp with
  /// null the next time a queued log re-synced.
  final String? soNo;
  final String? soIssuedAt;
  final String? timeGiven;

  /// A calendar day (`YYYY-MM-DD`) for a `date` column, never an instant —
  /// see SanitaryOrder.toDateOnly for why the distinction matters here.
  final String? deadline;

  /// The "Received by" line: the owner or point person acknowledging service
  /// on site, by name. (Signature pads were removed 2026-11-06; the printed
  /// form keeps a blank line for wet ink.)
  final String? receivedByName;

  // [REF: PROPOSED_CONTACT]
  /// The point person an inspector recorded in the field, for an admin to
  /// approve.
  ///
  /// Carried on the log rather than written straight to the establishment for
  /// two reasons, both structural: mobile has no write path to
  /// `establishments` at all (it only reads them), and this is the one table
  /// with an offline queue behind it — a contact recorded in a dead zone has
  /// to survive the trip back. Approving one copies it onto
  /// `establishments.point_person_email`, which is what the delivery function
  /// actually reads, and provisions the owner account.
  final String? proposedPointPersonName;
  final String? proposedPointPersonEmail;

  final List<Map<String, dynamic>> results;

  InspectionLog({
    String? id,
    required this.establishmentId,
    this.establishmentName,
    this.categoryId,
    this.categoryName,
    required this.inspectorName,
    required this.totalDemerits,
    required this.percentageRating,  // nullable, but never silently omitted
    this.remarks,
    String? inspectionDate,
    this.soNo,
    this.soIssuedAt,
    this.timeGiven,
    this.deadline,
    this.receivedByName,
    this.proposedPointPersonName,
    this.proposedPointPersonEmail,
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
      percentageRating: (json['percentage_rating'] as num?)?.toDouble(),
      remarks: json['remarks'] as String?,
      inspectionDate: json['inspection_date'] as String?,
      soNo: json['so_no'] as String?,
      soIssuedAt: json['so_issued_at'] as String?,
      timeGiven: json['time_given'] as String?,
      deadline: json['deadline'] as String?,
      receivedByName: json['received_by_name'] as String?,
      proposedPointPersonName: json['proposed_point_person_name'] as String?,
      proposedPointPersonEmail: json['proposed_point_person_email'] as String?,
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
      // [REF: SANITARY_ORDER_WRITE]
      // Omitted rather than nulled when no order was issued, for the same
      // reason as establishment_name: upsert() overwrites every key it is
      // given, so writing nulls here would erase an order that a previous
      // drain already landed. soIssuedAt is the marker; soNo may legitimately
      // be null on an order that exists.
      if (soIssuedAt != null) 'so_issued_at': _normalizeTimestamp(soIssuedAt!),
      if (soNo != null) 'so_no': soNo,
      if (timeGiven != null) 'time_given': timeGiven,
      if (deadline != null) 'deadline': deadline,
      if (receivedByName != null) 'received_by_name': receivedByName,
      // Omitted when absent like the rest of the order: upsert overwrites
      // every key it is handed, and nulling these on a retry would erase a
      // proposal an admin may already be looking at.
      if (proposedPointPersonName != null)
        'proposed_point_person_name': proposedPointPersonName,
      if (proposedPointPersonEmail != null)
        'proposed_point_person_email': proposedPointPersonEmail,
      'results': results,
    };
  }
}
