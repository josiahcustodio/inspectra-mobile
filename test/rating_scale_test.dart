import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clowtec_inspector/core/rating_scale.dart';

/// Regression tests for the sanitary rating bands.
///
/// These exist because the bands used to be copy-pasted into five places that
/// had quietly drifted apart (see `docs/ARCH_GUIDE.md` §5.2). They now live in
/// one module per client, and the second group below pins the exact values the
/// web dashboard's `src/lib/ratingScale.ts` must also carry — so if someone
/// edits one side of that hand-mirrored pair, this test says what the other
/// side is expected to hold.
void main() {
  group('band boundaries', () {
    test('every whole score 0–100 lands in exactly the documented band', () {
      for (var score = 0; score <= 100; score++) {
        final expected = score >= 90
            ? RatingBand.excellent
            : score >= 70
                ? RatingBand.verySatisfactory
                : RatingBand.satisfactory;
        expect(RatingScale.bandOf(score), expected, reason: 'score $score');
      }
    });

    test('boundaries are inclusive at the lower edge', () {
      expect(RatingScale.bandOf(69), RatingBand.satisfactory);
      expect(RatingScale.bandOf(70), RatingBand.verySatisfactory);
      expect(RatingScale.bandOf(89), RatingBand.verySatisfactory);
      expect(RatingScale.bandOf(90), RatingBand.excellent);
    });

    test('fractional scores classify by their band, not by rounding', () {
      // percentageRating is stored as a double, so these really do occur.
      expect(RatingScale.bandOf(69.9), RatingBand.satisfactory);
      expect(RatingScale.bandOf(89.9), RatingBand.verySatisfactory);
      expect(RatingScale.bandOf(89.999), RatingBand.verySatisfactory);
    });

    test('a negative score falls into the lowest band rather than throwing', () {
      expect(RatingScale.bandOf(-1), RatingBand.satisfactory);
    });

    test('a null score is unscored, not a band', () {
      expect(RatingScale.labelOf(null), RatingScale.unscoredLabel);
      expect(RatingScale.colorOf(null), RatingScale.unscoredColor);
      // The lowest band must not be reachable via null — that was the bug where
      // an unscored inspection rendered as a red 0% "Satisfactory".
      expect(RatingScale.labelOf(null),
          isNot(RatingScale.labelOfBand(RatingBand.satisfactory)));
    });
  });

  group('cross-client contract (must match src/lib/ratingScale.ts)', () {
    test('labels', () {
      expect(RatingScale.labelOfBand(RatingBand.excellent), 'Excellent');
      expect(RatingScale.labelOfBand(RatingBand.verySatisfactory),
          'Very Satisfactory');
      expect(RatingScale.labelOfBand(RatingBand.satisfactory), 'Satisfactory');
    });

    test('colours', () {
      expect(RatingScale.colorOfBand(RatingBand.excellent),
          const Color(0xFF10B981));
      expect(RatingScale.colorOfBand(RatingBand.verySatisfactory),
          const Color(0xFFF59E0B));
      expect(RatingScale.colorOfBand(RatingBand.satisfactory),
          const Color(0xFFEF4444));
    });

    test('bounds and their printable ranges agree', () {
      expect(RatingScale.rangeOfBand(RatingBand.excellent), '90–100');
      expect(RatingScale.rangeOfBand(RatingBand.verySatisfactory), '70–89');
      expect(RatingScale.rangeOfBand(RatingBand.satisfactory), '0–69');
    });

    test('the bands tile 0–100 with no gap and no overlap', () {
      final ascending = RatingScale.descending.reversed.toList();
      expect(RatingScale.minOfBand(ascending.first), 0);
      expect(RatingScale.maxOfBand(ascending.last), 100);
      for (var i = 0; i < ascending.length - 1; i++) {
        expect(
          RatingScale.minOfBand(ascending[i + 1]),
          RatingScale.maxOfBand(ascending[i]) + 1,
          reason: 'gap or overlap between ${ascending[i]} and ${ascending[i + 1]}',
        );
      }
    });

    test('descending really is ordered highest-first', () {
      final mins = RatingScale.descending.map(RatingScale.minOfBand).toList();
      final sorted = [...mins]..sort((a, b) => b.compareTo(a));
      expect(mins, sorted);
    });
  });
}
