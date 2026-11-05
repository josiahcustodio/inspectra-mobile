import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/establishment.dart';

// [REF: ESTABLISHMENT_DETAILS_CARD]
/// The masterlist record, for checking the inspector is at the right business.
///
/// Sits at the top of the scroll view rather than in [EstablishmentBanner]: the
/// banner is pinned and already competes with the checklist for height, while
/// this only matters before scoring starts and scrolls away on its own. Name,
/// owner and address are left to the banner directly above it.
class EstablishmentDetailsCard extends StatelessWidget {
  final Establishment establishment;

  const EstablishmentDetailsCard({super.key, required this.establishment});

  List<(String, String)> get _rows {
    final e = establishment;
    final personnel = e.personnelCount > 0
        ? '${e.personnelCount} (${e.personnelWithHc} with health card)'
        : null;
    final floorArea = e.floorAreaSqm == null ? null : '${e.floorAreaSqm} sqm';
    final rows = <(String, String?)>[
      ('Line of business', e.lineOfBusiness),
      ('Business permit no.', e.businessPermitNo),
      ('Permit date issued', e.permitDateIssued),
      ('Application type', e.applicType),
      ('Sanitary permit no.', e.sanitaryPermitNo),
      ('Control no.', e.controlNo),
      ('Telephone', e.telNo),
      ('TIN', e.tin),
      ('Floor area', floorArea),
      ('Personnel', personnel),
    ];
    return [
      for (final (label, value) in rows)
        if (value != null &&
            value.trim().isNotEmpty &&
            value.trim().toUpperCase() != 'N/A')
          (label, value.trim()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        // Open by default because verifying is the point; an inspector who
        // already knows the place can fold it away.
        child: ExpansionTile(
          initiallyExpanded: true,
          shape: const Border(),
          title: const Text(
            'Business information',
            style: TextStyle(
              fontFamily: '.SF Pro Display',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontFamily: '.SF Pro Text',
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontFamily: '.SF Pro Text',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
