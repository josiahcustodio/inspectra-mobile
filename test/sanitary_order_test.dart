import 'package:flutter_test/flutter_test.dart';

import 'package:clowtec_inspector/core/rating_scale.dart';
import 'package:clowtec_inspector/core/sanitary_order.dart';
import 'package:clowtec_inspector/data/models/checklist_template.dart';
import 'package:clowtec_inspector/providers/rating_provider.dart';

/// Pins the rules of the Sanitary Order (CHO-ESD-FR-04).
///
/// This document cites P.D. 856 / P.D. 522 and two city ordinances and tells
/// its recipient they are "liable for prosecution", so every rule here is one
/// whose failure mode is a wrong legal notice rather than a wrong number on a
/// dashboard. The cases below are the ones that were actually reachable in the
/// code before this module existed.
Map<String, dynamic> row(
  String id,
  String answer, {
  String note = '',
  String correction = '',
  String item = '',
}) =>
    {
      'checklist_item_id': id,
      'item_name': item.isEmpty ? 'Item $id' : item,
      'sub_category': 'Sub',
      'weight': 5,
      'answer': answer,
      'note': note,
      'correction': correction,
    };

void main() {
  group('defect selection', () {
    test('only Fail rows become defects', () {
      final defects = SanitaryOrder.defectsFrom([
        row('1', 'Pass'),
        row('2', 'Fail', note: 'No hairnet', correction: 'Provide hairnets'),
        row('3', 'NA'),
      ]);

      expect(defects, hasLength(1));
      expect(defects.single.checklistItemId, '2');
      expect(defects.single.defect, 'No hairnet');
      expect(defects.single.correction, 'Provide hairnets');
    });

    // [REF: SO_DEFECT_SOURCE]
    test('a stale note on an N/A row is NOT a defect', () {
      // Reachable before RatingProvider.setAnswer was fixed: a Fail flipped
      // to N/A kept its note. Selecting defects by note text — which the
      // log's `remarks` block still does — would cite a violation the
      // inspector had already withdrawn.
      final defects = SanitaryOrder.defectsFrom([
        row('1', 'NA', note: 'Withdrawn: this was my mistake'),
        row('2', 'Pass', note: 'leftover text'),
      ]);

      expect(defects, isEmpty);
    });

    test('an order is required exactly when there is a defect', () {
      expect(SanitaryOrder.isRequiredFor([row('1', 'Pass')]), isFalse);
      expect(SanitaryOrder.isRequiredFor([row('1', 'NA')]), isFalse);
      expect(SanitaryOrder.isRequiredFor([]), isFalse);
      expect(
        SanitaryOrder.isRequiredFor([row('1', 'Pass'), row('2', 'Fail')]),
        isTrue,
      );
    });

    test('missing keys degrade to empty strings rather than throwing', () {
      // `results` is written loosely by two clients over time (see
      // models.ts) — a legacy row may be missing `correction` entirely.
      final defects = SanitaryOrder.defectsFrom([
        {'checklist_item_id': '9', 'answer': 'Fail'},
      ]);

      expect(defects.single.defect, isEmpty);
      expect(defects.single.correction, isEmpty);
      expect(defects.single.item, isEmpty);
    });

    test('the Fail literal matches the one RatingProvider writes', () {
      final provider = RatingProvider();
      provider.init([
        ChecklistTemplate(id: '1', category: 'Cat', subCategory: 'Sub', item: 'Item 1', weight: 5),
      ]);
      provider.setAnswer('1', SanitaryOrder.failAnswer);

      // If the two ever drift, scoring and the order would disagree about
      // what a defect is — demerits on the record, nothing on the notice.
      expect(provider.totalDemerits, 5);
      expect(RatingScale.labelOf(provider.score), isNotEmpty);
    });
  });

  group('order number', () {
    // [REF: SO_NUMBER_NORMALIZE]
    test('blank normalizes to null, never to an empty string', () {
      // The series-year unique index ignores nulls but NOT empty strings:
      // two `''` rows collide and the second insert fails in the field.
      expect(SanitaryOrder.normalizeOrderNo(null), isNull);
      expect(SanitaryOrder.normalizeOrderNo(''), isNull);
      expect(SanitaryOrder.normalizeOrderNo('   '), isNull);
    });

    test('surrounding whitespace is stripped so one number is one number', () {
      expect(SanitaryOrder.normalizeOrderNo(' 47 '), '47');
      expect(SanitaryOrder.normalizeOrderNo('47'), '47');
    });

    test('the number is NOT reformatted — CHO\'s pattern is still unknown', () {
      // Deliberate: until the pattern is known, whatever is on the booklet
      // page is what gets recorded. '047' and '47' stay distinct rather than
      // being silently merged by a guess.
      expect(SanitaryOrder.normalizeOrderNo('047'), '047');
      expect(SanitaryOrder.normalizeOrderNo('2026-047-B'), '2026-047-B');
    });
  });

  // [REF: SO_CONTACT_NORMALIZE]
  group('point person email', () {
    test('blank normalizes to null, never an empty string', () {
      // The delivery function selects on `point_person_email is not null`;
      // an empty string passes that test and reaches nobody.
      expect(SanitaryOrder.normalizeEmail(null), isNull);
      expect(SanitaryOrder.normalizeEmail(''), isNull);
      expect(SanitaryOrder.normalizeEmail('   '), isNull);
    });

    test('case and whitespace are folded so one inbox is one address', () {
      expect(SanitaryOrder.normalizeEmail('  Juan@Example.COM '),
          'juan@example.com');
    });

    test('the shape check catches the typos that matter', () {
      expect(SanitaryOrder.looksLikeEmail('juan@example.com'), isTrue);
      expect(SanitaryOrder.looksLikeEmail('juan.dela-cruz@mail.example.ph'),
          isTrue);
      // Each of these would silently send a legal notice nowhere.
      expect(SanitaryOrder.looksLikeEmail('juan@example'), isFalse);
      expect(SanitaryOrder.looksLikeEmail('juanexample.com'), isFalse);
      expect(SanitaryOrder.looksLikeEmail('juan@.com'), isFalse);
      expect(SanitaryOrder.looksLikeEmail(''), isFalse);
    });
  });

  group('submit guard', () {
    List<SanitaryDefect> complete() => SanitaryOrder.defectsFrom([
          row('1', 'Fail', note: 'No hairnet', correction: 'Provide hairnets'),
        ]);

    String? blockerFor(
      List<SanitaryDefect> defects, {
      String? timeGiven = '7 days',
      DateTime? deadline,
      String? receivedByName = 'Juan Dela Cruz',
    }) =>
        SanitaryOrder.firstBlocker(
          defects: defects,
          timeGiven: timeGiven,
          deadline: deadline ?? DateTime(2026, 11, 1),
          receivedByName: receivedByName,
        );

    test('a complete order is issuable', () {
      expect(blockerFor(complete()), isNull);
    });

    test('no defects means nothing to block — a clean inspection just passes',
        () {
      expect(SanitaryOrder.firstBlocker(
        defects: const [],
        timeGiven: null,
        deadline: null,
        receivedByName: null,
      ), isNull);
    });

    // [REF: SO_SUBMIT_GUARD]
    test('a defect with no description blocks the order', () {
      // The deficiency field advertised itself as "(Required)" while nothing
      // enforced it. A blank left column is an unenforceable notice.
      final defects =
          SanitaryOrder.defectsFrom([row('1', 'Fail', correction: 'Fix it')]);
      expect(blockerFor(defects), contains('Describe the deficiency'));
    });

    test('a defect with no correction blocks the order', () {
      final defects =
          SanitaryOrder.defectsFrom([row('1', 'Fail', note: 'No hairnet')]);
      expect(blockerFor(defects), contains('recommended correction'));
    });

    test('note and correction are required even when no order is issued', () {
      final defects =
          SanitaryOrder.defectsFrom([row('1', 'Fail', note: 'No hairnet')]);
      expect(SanitaryOrder.defectBlocker(defects),
          contains('recommended correction'));
      expect(SanitaryOrder.defectBlocker(complete()), isNull);
    });

    test('whitespace does not satisfy either column', () {
      final defects = SanitaryOrder.defectsFrom(
          [row('1', 'Fail', note: '   ', correction: '  ')]);
      expect(blockerFor(defects), contains('Describe the deficiency'));
    });

    test('the blocking message names the failing item', () {
      final defects = SanitaryOrder.defectsFrom(
          [row('7', 'Fail', item: 'Handwashing facilities')]);
      expect(blockerFor(defects), contains('Handwashing facilities'));
    });

    test('time given, deadline, recipient and signature are each required',
        () {
      expect(blockerFor(complete(), timeGiven: ''), contains('time given'));
      expect(
        SanitaryOrder.firstBlocker(
          defects: complete(),
          timeGiven: '7 days',
          deadline: null,
          receivedByName: 'Juan',
        ),
        contains('deadline'),
      );
      expect(blockerFor(complete(), receivedByName: '  '),
          contains('received the Sanitary Order'));
    });

    test('a malformed point person email blocks the order', () {
      expect(
        SanitaryOrder.firstBlocker(
          defects: complete(),
          timeGiven: '7 days',
          deadline: DateTime(2026, 11, 1),
          receivedByName: 'Juan',
          pointPersonEmail: 'juan@example',
        ),
        contains('email address'),
      );
    });

    test('an absent point person email does not block it — it is optional',
        () {
      // An admin can add the address from the dashboard; the inspector is not
      // required to extract one on the spot.
      for (final value in [null, '', '   ']) {
        expect(
          SanitaryOrder.firstBlocker(
            defects: complete(),
            timeGiven: '7 days',
            deadline: DateTime(2026, 11, 1),
            receivedByName: 'Juan',
            pointPersonEmail: value,
          ),
          isNull,
          reason: 'blocked on ${value == null ? 'null' : '"$value"'}',
        );
      }
    });

    test('a valid point person email passes', () {
      expect(
        SanitaryOrder.firstBlocker(
          defects: complete(),
          timeGiven: '7 days',
          deadline: DateTime(2026, 11, 1),
          receivedByName: 'Juan',
          pointPersonEmail: ' Juan@Example.com ',
        ),
        isNull,
      );
    });

    test('defects are checked before the order-level fields', () {
      // One message at a time, and the per-item gap comes first: fixing the
      // table is what the inspector is standing in front of the defect for.
      final defects = SanitaryOrder.defectsFrom([row('1', 'Fail')]);
      expect(blockerFor(defects, timeGiven: '', receivedByName: ''),
          contains('Describe the deficiency'));
    });
  });

  group('deadline is a calendar day, not an instant', () {
    test('formats as YYYY-MM-DD with zero padding', () {
      expect(SanitaryOrder.toDateOnly(DateTime(2026, 1, 5)), '2026-01-05');
      expect(SanitaryOrder.toDateOnly(DateTime(2026, 11, 30)), '2026-11-30');
    });

    test('a late-evening local pick keeps its own date', () {
      // The reason this is not toUtc().toIso8601String(): 23:30 in Manila is
      // 15:30 UTC the same day, but the generic trap is a deadline that
      // slides a day under conversion. The date column must read back as the
      // day the inspector pointed at.
      expect(
        SanitaryOrder.toDateOnly(DateTime(2026, 11, 30, 23, 30)),
        '2026-11-30',
      );
    });
  });

  // [REF: ANSWER_CLEARS_DEFECT_TEXT]
  group('withdrawing a Fail withdraws its text', () {
    RatingProvider seeded() {
      final p = RatingProvider();
      p.init([
        ChecklistTemplate(id: '1', category: 'Cat', subCategory: 'Sub', item: 'Item 1', weight: 5),
      ]);
      p.setAnswer('1', 'Fail');
      p.setNote('1', 'No hairnet');
      p.setCorrection('1', 'Provide hairnets');
      return p;
    }

    test('flipping to N/A clears both columns', () {
      // The original bug: only 'Pass' cleared, so N/A kept the text.
      final p = seeded();
      p.setAnswer('1', 'NA');
      expect(p.itemNotes.containsKey('1'), isFalse);
      expect(p.itemCorrections.containsKey('1'), isFalse);
    });

    test('flipping to Pass clears both columns', () {
      final p = seeded();
      p.setAnswer('1', 'Pass');
      expect(p.itemNotes.containsKey('1'), isFalse);
      expect(p.itemCorrections.containsKey('1'), isFalse);
    });

    test('staying on Fail keeps them', () {
      final p = seeded();
      p.setAnswer('1', 'Fail');
      expect(p.itemNotes['1'], 'No hairnet');
      expect(p.itemCorrections['1'], 'Provide hairnets');
    });

    test('init and reset clear corrections along with everything else', () {
      final p = seeded();
      p.reset();
      expect(p.itemCorrections, isEmpty);

      final p2 = seeded();
      p2.init([
        ChecklistTemplate(id: '1', category: 'Cat', subCategory: 'Sub', item: 'Item 1', weight: 5),
      ]);
      expect(p2.itemCorrections, isEmpty);
    });
  });
}
