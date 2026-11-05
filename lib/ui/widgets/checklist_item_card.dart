import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/checklist_template.dart';
import '../../providers/rating_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_colors.dart';

class ChecklistItemCard extends StatelessWidget {
  final ChecklistTemplate item;

  const ChecklistItemCard({super.key, required this.item});

  IconData _getIconForSubCategory(String subCategory) {
    final lower = subCategory.toLowerCase();
    if (lower.contains('waste') || lower.contains('garbage')) return Icons.delete_outline_rounded;
    if (lower.contains('handwash') || lower.contains('water')) return Icons.water_drop_outlined;
    if (lower.contains('food')) return Icons.restaurant_outlined;
    if (lower.contains('personnel') || lower.contains('health')) return Icons.health_and_safety_outlined;
    if (lower.contains('permit') || lower.contains('document')) return Icons.description_outlined;
    if (lower.contains('pest')) return Icons.bug_report_outlined;
    if (lower.contains('toilet') || lower.contains('sanitary')) return Icons.wc_outlined;
    return Icons.check_circle_outline_rounded; // Default
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RatingProvider>(
      builder: (context, provider, child) {
        final currentAnswer = provider.answers[item.id];
        final isFail = currentAnswer == 'Fail';

        // Dynamic border coloring based on selection
        Color borderColor = AppTheme.border;
        // AppColors.pass, not AppTheme.primary: Pass is a verdict color and
        // must match how the same answer renders on the details screen —
        // brand green and verdict green are distinct tokens on purpose.
        if (currentAnswer == 'Pass') borderColor = AppColors.pass.withAlpha(100);
        if (currentAnswer == 'Fail') borderColor = AppColors.fail.withAlpha(100);
        if (currentAnswer == 'NA') borderColor = AppTheme.textSecondary.withAlpha(100);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppTheme.cardRadius,
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: AppTheme.softShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Scannable Icon
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getIconForSubCategory(item.subCategory),
                        color: AppTheme.textSecondary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Title and Description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.item, // Main Title
                            style: const TextStyle(
                              fontFamily: '.SF Pro Display',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.3,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.subCategory, // Using SubCategory as clarification line
                            style: const TextStyle(
                              fontFamily: '.SF Pro Text',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textSecondary,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // [REF: CHECKLIST_FIELDS] The form's blanks and Y/N boxes for
                // this item, above the verdict so the inspector records what
                // they measured before judging it. Optional: nothing here
                // blocks submit.
                for (final f in item.fields) ...[
                  _buildField(f, provider.itemValues[item.id]?[f.label], provider),
                  const SizedBox(height: 10),
                ],
                // Full-width Segmented Control
                _buildSegmentedControl(context, currentAnswer, provider),
                
                // [REF: SO_DEFECT_CAPTURE]
                // The two columns of the Sanitary Order's table, captured in
                // the inspector's own words at the moment they see the defect.
                // Both only exist on a Fail, and both are required by
                // SanitaryOrder.firstBlocker — an order that names a violation
                // without saying what to fix is not one anybody can comply
                // with, and a blank defect line is unenforceable.
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: isFail
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDefectField(
                                initialValue: provider.itemNotes[item.id] ?? '',
                                onChanged: (val) => provider.setNote(item.id, val),
                                // The form's own wording, so what the inspector
                                // types reads the same on screen and on paper.
                                hintText: 'Sanitary defect / violation (Required)...',
                                icon: Icons.edit_note_rounded,
                              ),
                              const SizedBox(height: 10),
                              _buildDefectField(
                                initialValue:
                                    provider.itemCorrections[item.id] ?? '',
                                onChanged: (val) =>
                                    provider.setCorrection(item.id, val),
                                hintText:
                                    'Recommended correction / action (Required)...',
                                icon: Icons.build_circle_outlined,
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildField(
      ChecklistField f, dynamic current, RatingProvider provider) {
    final List<String> options = switch (f.type) {
      'yesno' => const ['Yes', 'No'],
      'choice' || 'multi' => f.options,
      _ => const [],
    };
    if (options.isEmpty) {
      return TextFormField(
        initialValue: current?.toString() ?? '',
        keyboardType: f.type == 'number'
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        onChanged: (v) => provider.setValue(item.id, f.label, v),
        decoration: InputDecoration(
          labelText: f.label,
          hintText: f.type == 'date' ? 'YYYY-MM-DD' : null,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        style: const TextStyle(fontFamily: '.SF Pro Text', fontSize: 14),
      );
    }
    final multi = f.type == 'multi';
    final selected = multi
        ? (current as List?)?.map((e) => e.toString()).toSet() ?? <String>{}
        : {if (current != null) current.toString()};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(f.label,
            style: const TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final o in options)
              FilterChip(
                label: Text(o),
                selected: selected.contains(o),
                showCheckmark: multi,
                onSelected: (on) {
                  if (multi) {
                    final next = {...selected};
                    on ? next.add(o) : next.remove(o);
                    provider.setValue(item.id, f.label, next.toList());
                  } else {
                    provider.setValue(item.id, f.label, on ? o : null);
                  }
                },
              ),
          ],
        ),
      ],
    );
  }

  /// One of the two deficiency fields. Shared rather than duplicated because
  /// the only thing that differs between them is the hint, the icon and where
  /// the text goes.
  Widget _buildDefectField({
    required String initialValue,
    required ValueChanged<String> onChanged,
    required String hintText,
    required IconData icon,
  }) {
    return TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
            color: Colors.black38, fontFamily: '.SF Pro Text', fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.black38),
        filled: true,
        fillColor: Colors.red.shade50.withAlpha(128),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      ),
      style: const TextStyle(fontFamily: '.SF Pro Text', fontSize: 14),
    );
  }

  // [REF: PASS_FAIL_NA_CONTROL]
  Widget _buildSegmentedControl(BuildContext context, String? currentAnswer, RatingProvider provider) {
    final bool isPass = currentAnswer == 'Pass';
    final bool isFail = currentAnswer == 'Fail';
    final bool isNa = currentAnswer == 'NA';

    final String lowerSubCategory = item.subCategory.toLowerCase();
    final bool removeNa = lowerSubCategory.contains('water') || lowerSubCategory.contains('waste');

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _SegmentButton(
              label: 'PASS',
              icon: Icons.check_rounded,
              isSelected: isPass,
              selectedColor: AppColors.pass, // verdict green, same as FAIL's token below
              onTap: () => provider.setAnswer(item.id, 'Pass'),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SegmentButton(
              label: 'FAIL',
              icon: Icons.close_rounded,
              isSelected: isFail,
              selectedColor: AppColors.fail, // Vibrant Red
              onTap: () => provider.setAnswer(item.id, 'Fail'),
            ),
          ),
          if (!removeNa) ...[
            const SizedBox(width: 4),
            Expanded(
              child: _SegmentButton(
                label: 'N/A',
                icon: Icons.horizontal_rule_rounded,
                isSelected: isNa,
                selectedColor: AppTheme.textSecondary, // Slate Gray
                onTap: () => provider.setAnswer(item.id, 'NA'),
              ),
            ),
          ]
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: selectedColor.withAlpha(76), // 30% opacity
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
