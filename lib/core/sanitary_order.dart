/// The Sanitary Order (CHO-ESD-FR-04) derived from one inspection.
///
/// The one place the rules of the order live, for the same reason
/// [RatingScale] exists: what prints on this document is a legal notice under
/// P.D. 856 / P.D. 522 and the city ordinances named on the form, so the
/// questions "which items are defects?" and "is this order complete?" must
/// have exactly one answer, testable without a running app.
///
/// Scope note: this module decides nothing about *delivery*. The order is
/// served on site — the owner signs the "Received by" line at the inspection
/// — and any emailed copy is a convenience afterwards.
library;

/// One row of the form's two-column defect table.
typedef SanitaryDefect = ({
  String checklistItemId,
  String item,
  String subCategory,
  String defect,
  String correction,
});

class SanitaryOrder {
  SanitaryOrder._();

  /// The answer that makes a checklist item a defect. Mirrors the literal
  /// `'Fail'` written by [RatingProvider.setAnswer] and scored by
  /// `totalDemerits`.
  static const String failAnswer = 'Fail';

  // [REF: SO_DEFECT_SOURCE]
  /// The left column of the form, read off an inspection's `results` array.
  ///
  /// Filters on `answer == 'Fail'` and NEVER on "has a note". Those two were
  /// the same thing only by accident: `setAnswer` used to clear an item's note
  /// when it flipped to Pass but not when it flipped to N/A, so a withdrawn
  /// deficiency could keep its text. Selecting by note would then print a
  /// violation the inspector had already taken back — onto a document that
  /// renders the establishment "liable for prosecution". The answer is the
  /// verdict; the note is only its description.
  static List<SanitaryDefect> defectsFrom(List<Map<String, dynamic>> results) {
    return results
        .where((row) => row['answer'] == failAnswer)
        .map((row) => (
              checklistItemId: (row['checklist_item_id'] ?? '').toString(),
              item: (row['item_name'] ?? '').toString(),
              subCategory: (row['sub_category'] ?? '').toString(),
              defect: (row['note'] ?? '').toString().trim(),
              correction: (row['correction'] ?? '').toString().trim(),
            ))
        .toList(growable: false);
  }

  /// Whether this inspection has to issue an order at all.
  ///
  /// One defect is enough: the form's premise is "the defects listed [...] are
  /// observed". A spotless inspection issues nothing, so the inspector is
  /// never asked for a deadline or an owner's name they have no reason
  /// to collect.
  static bool isRequiredFor(List<Map<String, dynamic>> results) =>
      defectsFrom(results).isNotEmpty;

  // [REF: SO_NUMBER_NORMALIZE]
  /// The order number as it should be stored, or null for "not numbered yet".
  ///
  /// Blank MUST become null rather than `''`. The series-year unique index on
  /// `so_no` ignores nulls (`null != null` in SQL), so any number of
  /// unnumbered orders coexist — but two empty strings collide, and the second
  /// one would fail its insert in the field, offline, on a legal record.
  ///
  /// shortcut: no format rule — CHO's numbering pattern is still unknown (the
  /// field is typed off their pre-numbered booklet). When they supply it, add
  /// the pattern here and backfill via
  /// `so_issued_at is not null and so_no is null`.
  static String? normalizeOrderNo(String? raw) {
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  // [REF: SO_CONTACT_NORMALIZE]
  /// An email address as it should be stored, or null for "not recorded".
  ///
  /// Lower-cased as well as trimmed: this address is matched and de-duplicated
  /// downstream, and "Juan@x.com" and "juan@x.com" are one inbox. Blank
  /// becomes null, never '', because the delivery function selects on
  /// `point_person_email is not null` and an empty string passes that test
  /// while reaching nobody.
  static String? normalizeEmail(String? raw) {
    final trimmed = raw?.trim().toLowerCase() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Matches the login screen's own validator, deliberately — one address
  /// shape for the whole app. Not RFC-complete and not trying to be: it
  /// catches the typo that silently sends a legal notice nowhere (or, worse,
  /// to a stranger), which is what this is for.
  static final RegExp _emailShape =
      RegExp(r'^[\w.-]+@[\w.-]+\.[a-zA-Z]{2,}$');

  static bool looksLikeEmail(String value) => _emailShape.hasMatch(value);

  /// Why [raw] cannot be recorded as the point person's address, or null. Blank
  /// is fine: the field is optional, but a malformed one is refused rather than
  /// stored, since its use is to carry legal notices somewhere.
  static String? emailBlocker(String? raw) {
    final email = normalizeEmail(raw);
    if (email == null || looksLikeEmail(email)) return null;
    return 'Check the point person\'s email address — a typo would send '
        'notices to the wrong place, or nowhere.';
  }

  // [REF: SO_SUBMIT_GUARD]
  /// The first reason this order cannot be issued, or null when it is
  /// complete. Returns one message at a time on purpose: the inspector fixes
  /// it and resubmits, rather than reading a list.
  ///
  /// Every defect needs BOTH columns of the table filled. The deficiency-note
  /// field has advertised itself as "(Required)" since it was written while
  /// nothing enforced it — tolerable for a score, not for a document that
  /// prints the defect and its ordered correction side by side. A blank line
  /// there is an unenforceable order.
  ///
  /// [orderNo] is deliberately absent: the number is the one soft field until
  /// CHO's pattern is known. [pointPersonEmail] is optional too — an admin can
  /// add it from the dashboard — but a malformed one is refused rather than
  /// stored, since its only use is to carry a legal notice somewhere.
  static String? firstBlocker({
    required List<SanitaryDefect> defects,
    required String? timeGiven,
    required DateTime? deadline,
    required String? receivedByName,
    String? pointPersonEmail,
  }) {
    if (defects.isEmpty) return null; // nothing to order

    for (final d in defects) {
      final name = d.item.isEmpty ? d.checklistItemId : d.item;
      if (d.defect.isEmpty) {
        return 'Describe the deficiency for "$name" — it is printed as the '
            'violation on the Sanitary Order.';
      }
      if (d.correction.isEmpty) {
        return 'Add the recommended correction for "$name" — an order must '
            'say what has to be fixed.';
      }
    }

    if ((timeGiven ?? '').trim().isEmpty) {
      return 'Enter the time given for correction.';
    }
    if (deadline == null) {
      return 'Set the deadline for correction.';
    }
    if ((receivedByName ?? '').trim().isEmpty) {
      return 'Enter the name of the person who received the Sanitary Order.';
    }
    return emailBlocker(pointPersonEmail);
  }

  /// A `date` column wants a calendar day, not an instant: the deadline is
  /// "correct this by the 30th" as read in Batangas City, and sending a UTC
  /// timestamp would let a late-evening Manila pick land on the previous day.
  static String toDateOnly(DateTime deadline) =>
      '${deadline.year.toString().padLeft(4, '0')}-'
      '${deadline.month.toString().padLeft(2, '0')}-'
      '${deadline.day.toString().padLeft(2, '0')}';
}
