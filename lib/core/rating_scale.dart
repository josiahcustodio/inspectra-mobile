import 'package:flutter/material.dart';

/// [REF: RATING_SCALE]
/// The one place the sanitary rating bands are defined for the mobile app.
///
/// A score is always a whole percentage from 0 to 100 (it starts at 100 and
/// each failed checklist item deducts that item's demerit weight), and every
/// score falls into exactly one of three bands:
///
///   *  0 – 69  Satisfactory       red
///   * 70 – 89  Very Satisfactory  yellow
///   * 90 – 100 Excellent          green
///
/// The web dashboard mirrors this in `src/lib/ratingScale.ts`. If a band,
/// label or colour ever changes, change it in both places together.
enum RatingBand {
  satisfactory,
  verySatisfactory,
  excellent,
}

class RatingScale {
  RatingScale._();

  /// 90 – 100
  static const Color excellentColor = Color(0xFF10B981); // Emerald
  /// 70 – 89
  static const Color verySatisfactoryColor = Color(0xFFF59E0B); // Amber
  /// 0 – 69
  static const Color satisfactoryColor = Color(0xFFEF4444); // Red

  /// Shown instead of a band when no score exists yet. The web dashboard's
  /// equivalent reads "Not yet inspected", because over there a missing score
  /// means no inspection exists for the establishment at all; here it means an
  /// inspection form that is open but not finished. Different states, so the
  /// wording is deliberately different.
  static const String unscoredLabel = 'Not Scored Yet';
  static const Color unscoredColor = Color(0xFF94A3B8); // Slate

  /// Highest band first. [bandOf] walks this list, and legends can render it
  /// in the order a reader expects.
  static const List<RatingBand> descending = [
    RatingBand.excellent,
    RatingBand.verySatisfactory,
    RatingBand.satisfactory,
  ];

  /// Inclusive lower bound of a band. Together with [maxOfBand] this is the
  /// ONLY place a threshold number is written: [bandOf] classifies by reading
  /// these rather than repeating 90/70 in its own if-ladder, and [rangeOfBand]
  /// formats its text from the same numbers.
  static int minOfBand(RatingBand band) {
    switch (band) {
      case RatingBand.excellent:
        return 90;
      case RatingBand.verySatisfactory:
        return 70;
      case RatingBand.satisfactory:
        return 0;
    }
  }

  /// Inclusive upper bound of a band.
  static int maxOfBand(RatingBand band) {
    switch (band) {
      case RatingBand.excellent:
        return 100;
      case RatingBand.verySatisfactory:
        return 89;
      case RatingBand.satisfactory:
        return 69;
    }
  }

  static RatingBand bandOf(num score) {
    // Highest band first, so the first lower bound the score clears is its band.
    for (final band in descending) {
      if (score >= minOfBand(band)) return band;
    }
    // Unreachable for a 0–100 score; a negative one lands in the lowest band.
    return RatingBand.satisfactory;
  }

  static String labelOfBand(RatingBand band) {
    switch (band) {
      case RatingBand.excellent:
        return 'Excellent';
      case RatingBand.verySatisfactory:
        return 'Very Satisfactory';
      case RatingBand.satisfactory:
        return 'Satisfactory';
    }
  }

  static Color colorOfBand(RatingBand band) {
    switch (band) {
      case RatingBand.excellent:
        return excellentColor;
      case RatingBand.verySatisfactory:
        return verySatisfactoryColor;
      case RatingBand.satisfactory:
        return satisfactoryColor;
    }
  }

  /// The band range as it should read in help text and legends, e.g. "70–89".
  static String rangeOfBand(RatingBand band) =>
      '${minOfBand(band)}–${maxOfBand(band)}';

  /// `null` score means the inspection is not fully answered yet.
  static String labelOf(num? score) =>
      score == null ? unscoredLabel : labelOfBand(bandOf(score));

  static Color colorOf(num? score) =>
      score == null ? unscoredColor : colorOfBand(bandOf(score));
}
