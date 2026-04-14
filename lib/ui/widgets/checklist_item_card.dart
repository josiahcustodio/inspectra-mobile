import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/checklist_template.dart';
import '../../providers/rating_provider.dart';

class ChecklistItemCard extends StatelessWidget {
  final ChecklistTemplate item;

  const ChecklistItemCard({super.key, required this.item});

  IconData _getIconForSubCategory(String subCategory) {
    final lower = subCategory.toLowerCase();
    if (lower.contains('waste') || lower.contains('garbage')) return Icons.delete_outline;
    if (lower.contains('handwash') || lower.contains('water')) return Icons.water_drop_outlined;
    if (lower.contains('food')) return Icons.restaurant_outlined;
    if (lower.contains('personnel') || lower.contains('health')) return Icons.health_and_safety_outlined;
    if (lower.contains('permit') || lower.contains('document')) return Icons.description_outlined;
    if (lower.contains('pest')) return Icons.bug_report_outlined;
    if (lower.contains('toilet') || lower.contains('sanitary')) return Icons.wc_outlined;
    return Icons.check_circle_outline; // Default
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RatingProvider>(
      builder: (context, provider, child) {
        final currentAnswer = provider.answers[item.id];
        final isFail = currentAnswer == 'Fail';

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
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
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getIconForSubCategory(item.subCategory),
                        color: Colors.grey.shade700,
                        size: 28,
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
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                              letterSpacing: -0.3,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.subCategory, // Using SubCategory as clarification line
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Segmented Button
                    _buildSegmentedControl(context, currentAnswer, provider),
                  ],
                ),
                // Expanded Notes Area for Failures
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: isFail
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: TextFormField(
                            initialValue: provider.itemNotes[item.id] ?? '',
                            onChanged: (val) => provider.setNote(item.id, val),
                            decoration: InputDecoration(
                              hintText: 'Add deficiency notes...',
                              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                              prefixIcon: Icon(Icons.edit_note, color: Colors.grey.shade400),
                              filled: true,
                              fillColor: Colors.red.shade50.withValues(alpha: 0.5),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            style: const TextStyle(fontSize: 14),
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

  Widget _buildSegmentedControl(BuildContext context, String? currentAnswer, RatingProvider provider) {
    final bool isPass = currentAnswer == 'Pass';
    final bool isFail = currentAnswer == 'Fail';

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SegmentButton(
            label: 'PASS',
            isSelected: isPass,
            selectedColor: const Color(0xFF4CAF50), // Soft Green
            onTap: () => provider.setAnswer(item.id, 'Pass'),
          ),
          const SizedBox(width: 4),
          _SegmentButton(
            label: 'FAIL',
            isSelected: isFail,
            selectedColor: const Color(0xFFF44336), // Warning Red
            onTap: () => provider.setAnswer(item.id, 'Fail'),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: selectedColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey.shade500,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
