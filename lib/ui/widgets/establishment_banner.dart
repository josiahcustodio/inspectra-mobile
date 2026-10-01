import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/establishment.dart';

/// Type size of the owner and address rows. Named because the banner reasons
/// about its own height from it.
const double _supportingFontSize = 12;

// [REF: BANNER_DENSITY]
/// How much of the banner is showing, in order of the vertical space it claims.
///
/// The business name appears in all three: every tap the inspector makes is
/// attributed to that establishment, so losing the name mid-checklist is how a
/// score ends up on the wrong business. The address is what gives way, because
/// it is the longest and the least needed once the inspection is under way.
enum BannerDensity {
  /// Name, owner, and an address allowed to wrap onto a second line.
  full,

  /// Same rows, address clipped to one line.
  compact,

  /// Name and owner only.
  minimal,
}

// [REF: ESTABLISHMENT_BANNER]
/// Pinned identity strip for the live inspection form (D16 — that screen only).
///
/// Business name, owner, address, and nothing else: barangay, the category
/// badge, the sanitary permit and control numbers and the raw document id are
/// all deliberately absent (D1).
///
/// Nothing here is a fixed height, and that is the point. The banner shares the
/// top of the screen with the live score header, which measures about 96pt on
/// its own, so on a 320x568 device the pinned chrome is already close to a
/// third of the body. A hard-coded banner height would have to be sized for the
/// two-line-address worst case, waste that space in the common case, and clip
/// outright once the system text scale passes roughly 1.3. Instead every row is
/// intrinsically sized and the screen sheds rows as the checklist scrolls.
class EstablishmentBanner extends StatelessWidget {
  final Establishment establishment;
  final BannerDensity density;

  const EstablishmentBanner({
    super.key,
    required this.establishment,
    this.density = BannerDensity.full,
  });

  // [REF: BANNER_DENSITY_THRESHOLDS]
  /// Picks a density for a scroll offset, given the one in force.
  ///
  /// The gap between each collapse threshold and its matching re-expand
  /// threshold is load-bearing, not polish. Shedding a row makes the scroll
  /// viewport taller, which lowers `maxScrollExtent`, which can drag the offset
  /// back down — on a short checklist, far enough to recross the line it just
  /// crossed, at which point the row returns and the cycle repeats.
  ///
  /// So each gap has to be wider than the row that step sheds. The widest shed
  /// is a supporting row at the 1.3 scale cap: `2 + 12 * 1.3 * 1.2` ≈ 21pt.
  /// Both gaps are 24. An earlier 32/16 pair gave only 16 and left the band
  /// above scale 1.111 exposed — which includes 1.15 and 1.3, two of the
  /// stops Android's font-size slider actually offers.
  static BannerDensity densityFor(double offset, BannerDensity current) {
    const double collapseAt = 32;
    const double expandAt = 8;
    const double dropAt = 112;
    const double restoreAt = 88;

    switch (current) {
      case BannerDensity.full:
        return offset >= collapseAt ? BannerDensity.compact : BannerDensity.full;
      case BannerDensity.compact:
        if (offset >= dropAt) return BannerDensity.minimal;
        return offset < expandAt ? BannerDensity.full : BannerDensity.compact;
      case BannerDensity.minimal:
        if (offset < expandAt) return BannerDensity.full;
        return offset < restoreAt ? BannerDensity.compact : BannerDensity.minimal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);

    // The name is the invariant, so it keeps the reader's full text scale and
    // is given two lines to use. The supporting rows are capped: past ~1.3 they
    // would push the checklist off the screen to restate what the name already
    // told the inspector.
    final supportingScaler = scaler.clamp(maxScaleFactor: 1.3);

    // A second address line costs about what the owner row costs. Once the
    // reader has scaled text up, that budget is already spent, so the wrap is
    // traded away before the checklist is.
    final wrapFits =
        scaler.scale(_supportingFontSize) <= _supportingFontSize * 1.3;

    // When the address was never going to wrap — a short address, or a text
    // scale past 1.3 — `compact` would render identically to `full`, so the
    // FIRST collapse step would reclaim nothing, in exactly the configuration
    // where space is tightest. Folding it into `minimal` moves the duplicate
    // rung to the back of the ladder instead: `compact` and `minimal` then
    // render alike, and it is the 112/88 step that does nothing. Harmless
    // there — by that point the space has already been reclaimed — whereas
    // at the front it cost the inspector the one step that mattered.
    final effective = density == BannerDensity.compact && !wrapFits
        ? BannerDensity.minimal
        : density;
    final addressLines = effective == BannerDensity.full && wrapFits ? 2 : 1;

    final name = establishment.name.trim();
    final owner = establishment.ownerName.trim();
    final address = establishment.formattedAddress.trim();

    // `Establishment.fromJson` substitutes the literal string 'N/A' for a
    // missing address, which is worth a line of a 320pt-wide screen only if it
    // tells the inspector something.
    final hasAddress = address.isNotEmpty && address.toUpperCase() != 'N/A';

    // Animated rather than snapped. The checklist slides up under the banner as
    // it shrinks, and an instant jump of 15 to 30pt mid-scroll reads as a
    // rendering fault. `AnimatedSize` also clips during the transition, so a
    // row on its way out cannot overflow on the frame it is removed.
    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              // Two lines at every density, including `minimal`. Dropping to
              // one would reclaim real space — about 17pt, more than the
              // address row sheds — but it is the one trade this widget must
              // not make: two branches of the same chain differ only in the
              // tail of their name, and a single line at a large text scale
              // ellipsizes both to the same prefix. Space comes from the
              // address and from the keyboard yield instead.
              name.isEmpty ? 'Unnamed establishment' : name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: '.SF Pro Display',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                height: 1.15,
                letterSpacing: -0.2,
              ),
            ),
            if (owner.isNotEmpty) ...[
              const SizedBox(height: 2),
              _DetailRow(
                icon: Icons.person_outline_rounded,
                text: owner,
                maxLines: 1,
                textScaler: supportingScaler,
              ),
            ],
            if (hasAddress && effective != BannerDensity.minimal) ...[
              const SizedBox(height: 2),
              _DetailRow(
                icon: Icons.place_outlined,
                text: address,
                maxLines: addressLines,
                textScaler: supportingScaler,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One secondary line. The icon stands in for a label — "Owner:" and
/// "Address:" would spend characters this width cannot spare.
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final int maxLines;
  final TextScaler textScaler;

  const _DetailRow({
    required this.icon,
    required this.text,
    required this.maxLines,
    required this.textScaler,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            textScaler: textScaler,
            style: const TextStyle(
              fontFamily: '.SF Pro Text',
              fontSize: _supportingFontSize,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}
