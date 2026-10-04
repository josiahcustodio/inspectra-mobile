import 'package:flutter/material.dart';

/// [REF: COLOR_TOKENS]
/// Every colour the app draws with, named once.
///
/// This file exists because the same hex was being retyped in nine files and
/// had already drifted: the four auth screens had acquired a second brand
/// colour of their own (teal `#0D9488`) while every tab used emerald, so an
/// inspector watched the app change colour one second after signing in. There
/// is no longer anywhere else to write a colour down — a `Color(0xFF…)`
/// literal outside this file is a bug, and `flutter analyze` will not catch
/// it, so a grep for `0xFF` is part of the pre-push checklist.
///
/// **The three rating-band colours are deliberately NOT here.** They live in
/// `core/rating_scale.dart`, which is a cross-client contract mirrored by the
/// web dashboard's `src/lib/ratingScale.ts` and pinned by
/// `test/rating_scale_test.dart` — a test that names the web file and fails if
/// the hexes drift. Copying them into this file would give a band two homes
/// and let one change without the other. Ask [RatingScale] for a score's
/// colour; never reach for a green here.
class AppColors {
  AppColors._();

  // ─── Brand ──────────────────────────────────────────────────────────────
  //
  // Deep emerald, not mint. Three things decided this value, and all three are
  // worth knowing before anyone changes it:
  //
  //  1. It is already the web dashboard's brand — `--primary` in
  //     `src/styles/theme.css`. The two apps are one system to the City Health
  //     Office, and they now agree.
  //  2. It is NOT `#10B981`. That hex means exactly one thing in this product,
  //     "Excellent", and it was previously doing double duty as the app's
  //     entire chrome — so every green button carried the colour of a passing
  //     sanitary grade. Brand and verdict must be distinguishable.
  //  3. Contrast. `#10B981` on white is 2.56:1, which fails WCAG AA even for
  //     large text; the old auth teal was 3.74:1. This is 3.77:1 — enough for
  //     fills, icons and large display text, but not for body copy, which is
  //     what [brandStrong] is for.

  /// Fills, icons, active states, and display text at 24pt and above.
  static const Color brand = Color(0xFF059669);

  /// The same hue one step darker, at 5.48:1 on white — passes AA both as
  /// small text on a light ground and as white text on a brand fill. Use this
  /// for anything at body size: links, button labels, 11–16pt text.
  static const Color brandStrong = Color(0xFF047857);

  /// Pale mint ground for brand-tinted surfaces (avatar backgrounds, chips).
  static const Color brandSurface = Color(0xFFECFDF5);

  // ─── Text ───────────────────────────────────────────────────────────────

  /// Body and heading text.
  static const Color textPrimary = Color(0xFF1A1C1E);

  /// Used by the inspection form and the dialog titles for large display
  /// numerals and headings.
  ///
  /// A near-twin of [textPrimary] — two darks that differ by about as much as
  /// a display can show, inherited from two different screens being built at
  /// different times. Both are named rather than silently merged because
  /// collapsing them is a visual change on eight screens and belongs in its
  /// own commit, not in the one that introduced this file. Worth doing.
  static const Color textDisplay = Color(0xFF0F172A);

  /// Captions, secondary rows, hints, disabled labels.
  static const Color textSecondary = Color(0xFF64748B);

  // ─── Surfaces ───────────────────────────────────────────────────────────

  /// Cards, sheets, app bars.
  static const Color surface = Colors.white;

  /// The scaffold ground, and the fill behind inset fields.
  ///
  /// Absorbed `#F5F7FA` (the inspection form's scaffold) and `#E0E0E0`'s
  /// lighter sibling: three off-whites within two points of each other, which
  /// no screen can tell apart and no reader was ever meant to.
  static const Color background = Color(0xFFF8FAFC);

  // ─── Lines ──────────────────────────────────────────────────────────────

  /// Hairline borders, dividers, field outlines.
  ///
  /// Also absorbed the neutral `#E0E0E0` that the login fields used — at one
  /// physical pixel the slate tint is not distinguishable, and having two
  /// border greys is how a form ends up with mismatched outlines.
  static const Color border = Color(0xFFE2E8F0);

  /// A heavier border for an element that has to read as a drop target —
  /// the photo-evidence tile.
  static const Color borderStrong = Color(0xFFCBD5E1);

  // ─── Semantic: a checklist answer ───────────────────────────────────────
  //
  // Separate from both the brand and the rating bands. These mark one item's
  // answer, not an establishment's grade. They happen to be the same green and
  // red as the Excellent and Satisfactory bands, because good is green and bad
  // is red in both vocabularies — but they are a different concept and are
  // free to diverge, which is why they are stated here rather than borrowed
  // from [RatingScale].

  /// A passing / compliant checklist answer.
  static const Color pass = Color(0xFF10B981);

  /// A failing / non-compliant checklist answer, and destructive actions.
  static const Color fail = Color(0xFFEF4444);
}
