import 'package:flutter/material.dart';

import '../../core/category_suggester.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/inspection_category.dart';

/// Cap on the open menu's height.
///
/// Eleven categories at a bare 48pt each would already be ~528pt, and these
/// rows are not bare: `_EntryLabel` can run to two lines of name plus two of
/// reason, so the real list comfortably exceeds the 568pt test device's whole
/// screen. Bounded here so the menu scrolls rather than being squeezed or
/// overflowing its anchor. The figure is derived from source, not measured on
/// a device.
const double _menuMaxHeight = 320;

// [REF: CATEGORY_PICKER]
/// Chooses the checklist a live inspection is scored against (D4).
///
/// The category is picked here, at inspection time, and not read off the
/// establishment. `DropdownMenu` carries `enableFilter` and
/// `requestFocusOnTap` natively, so type-to-filter across eleven categories
/// costs no package and no custom search field.
///
/// Rows for unselectable categories are rendered **disabled, with their
/// reason**, never dropped (D25). Availability is not decided here — it
/// arrives already decided on each [CategoryOption], so the picker and the
/// submit guard cannot disagree about what is inspectable.
/// Known gap, to confirm in the Chunk 6 device pass: the field text can be
/// left showing a half-typed filter.
///
/// `DropdownMenu` keeps its field text in its own `State` and rewrites it in
/// only five places — `initState`, `didUpdateWidget` when `initialSelection`
/// changes, pressing an entry, arrow-key highlighting, and submitting while an
/// entry is highlighted. There is no `onClose` or tap-outside handler, so none
/// of them fire when the inspector types a filter and then taps away without
/// selecting, and the field can be left reading `lau` over a loaded Food
/// checklist.
///
/// A second route into the same state: the menu's own search ignores whether
/// an entry is enabled, so typing `live` highlights the disabled Livestock
/// Farm row, and pressing the keyboard's done key then takes neither branch of
/// `_handleSubmitted` — no selection, no revert, no feedback.
///
/// Display only in both cases: the submitted log takes its category from the
/// form's `_category`, never from this field. Not fixed here because every
/// candidate fix (a focus listener rewriting an injected controller, re-keying
/// on focus loss) changes framework-interaction behaviour that cannot be
/// verified without a running frame, and this chunk has had no device run.
class CategoryPicker extends StatelessWidget {
  final List<CategoryOption> options;

  /// The `categories` doc id currently chosen, or null before the first pick.
  final String? selectedCategoryId;

  /// What the keyword rules proposed for this establishment's name, if
  /// anything. Already validated against what is selectable.
  final CategorySuggestion? suggestion;

  final ValueChanged<CategoryOption> onSelected;

  const CategoryPicker({
    super.key,
    required this.options,
    required this.selectedCategoryId,
    required this.suggestion,
    required this.onSelected,
  });

  CategoryOption? _optionFor(String? categoryId) {
    if (categoryId == null) return null;
    for (final option in options) {
      if (option.category.id == categoryId) return option;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final suggested = _optionFor(suggestion?.categoryId);
    final suggestedFrom = suggestion?.keyword;

    // [REF: CATEGORY_PICKER_EMPTY]
    // A `DropdownMenu` with no entries is not an empty list — it is a control
    // that opens onto nothing and says nothing, while the label still invites
    // a tap. That state is reachable on a first launch with no signal: the
    // `categories` box is new in this chunk and only syncData fills it, so a
    // fresh install that has never been online has no rows to offer. Naming
    // the cause here is the difference between an inspector who knows to find
    // signal and one who concludes the app is broken.
    if (options.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 18, color: AppTheme.textSecondary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'No checklist categories on this device yet. Connect to the '
                'internet once to download them.',
                style: TextStyle(
                  fontFamily: '.SF Pro Text',
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LayoutBuilder because DropdownMenu does NOT size itself to its
          // parent — left to itself it measures its widest entry, and the
          // widest here is 61 characters ("Hotels, Motels, Apartments,
          // Condominiums and Transient Houses"), which on a 320pt screen would
          // push an unbounded child into the pinned Column this form already
          // clips at text scale 2.0.
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return DropdownMenu<String>(
                width: width,
                menuHeight: _menuMaxHeight,
                initialSelection: selectedCategoryId,
                enableFilter: true,
                requestFocusOnTap: true,
                label: const Text('Checklist category'),
                hintText: 'Choose a category',
                leadingIcon: const Icon(Icons.fact_check_outlined, size: 20),
                // The id, not the name: name matching is the hazard D24
                // removes, and two live categories are still both called
                // "Food".
                dropdownMenuEntries: [
                  for (final option in options)
                    DropdownMenuEntry<String>(
                      value: option.category.id,
                      // `label` stays the bare name because the built-in
                      // filter matches against this string; the reason line
                      // must not become something an inspector can search for.
                      label: option.category.name,
                      enabled: option.isSelectable,
                      // No width passed down. Because `width` is set on the
                      // DropdownMenu above, Flutter already wraps every
                      // `labelWidget` in a ConstrainedBox of
                      // `width - horizontalPadding` (dropdown_menu.dart), and
                      // that allowance is 64pt here once the field's leading
                      // icon has been measured — tighter than anything this
                      // file was reserving by hand. A second constraint would
                      // only wrap the long names earlier for no benefit.
                      labelWidget: _EntryLabel(option: option),
                    ),
                ],
                onSelected: (id) {
                  final option = _optionFor(id);
                  // The null check is load-bearing, not defensive padding:
                  // `DropdownMenu` calls `onSelected(null)` whenever the field
                  // is submitted with nothing highlighted, which an inspector
                  // reaches by typing a filter that matches no category and
                  // pressing the keyboard's done key.
                  if (option != null) onSelected(option);
                },
              );
            },
          ),
          // [REF: CATEGORY_SUGGESTION_HINT]
          // Shown only while nothing is picked. A suggestion is an opening
          // offer, not an annotation of a decision already made, and leaving it
          // on screen afterwards invites a reader of a screenshot to think the
          // app chose.
          //
          // Hint-only, deliberately NOT pre-selected. A pre-filled field
          // records identically to a considered choice, and this value lands on
          // a government audit record; the inspector has to put it there. It
          // also keeps the "no category picked" submit guard meaningful instead
          // of unreachable. The cost is one extra tap, and the tap is right
          // here.
          if (suggestedFrom != null &&
              suggested != null &&
              selectedCategoryId == null)
            _SuggestionHint(
              option: suggested,
              keyword: suggestedFrom,
              onAccept: () => onSelected(suggested),
            ),
        ],
      ),
    );
  }
}

/// One menu row: the category name, plus why it cannot be chosen.
class _EntryLabel extends StatelessWidget {
  final CategoryOption option;

  const _EntryLabel({required this.option});

  @override
  Widget build(BuildContext context) {
    final reason = option.unavailableLabel;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            option.category.name,
            // Two lines rather than one: the longest names here run to 61 and
            // 56 characters ("Hotels, Motels, Apartments, Condominiums and
            // Transient Houses" and "Day Care, Pre-School Services and
            // Children's Institution"). One ellipsized line would still name
            // the right form — they diverge at the first word — but it would
            // cut the enumerations that are the whole point of these titles,
            // and an inspector checking whether "Transient Houses" is covered
            // would have no way to tell from the row.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: '.SF Pro Text',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: option.isSelectable
                  ? AppTheme.textPrimary
                  : AppTheme.textSecondary,
            ),
          ),
          // The reason rides inside the label rather than in `trailingIcon`:
          // trailing content gets no width budget of its own in a
          // DropdownMenuEntry, so a sentence there would fight the name for the
          // same row and lose unpredictably.
          if (reason != null)
            Text(
              reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                fontStyle: FontStyle.italic,
                color: AppTheme.textSecondary,
              ),
            ),
      ],
    );
  }
}

/// The explainable half of D6: what was suggested, and on what evidence.
class _SuggestionHint extends StatelessWidget {
  final CategoryOption option;
  final String keyword;
  final VoidCallback onAccept;

  const _SuggestionHint({
    required this.option,
    required this.keyword,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      // Wrap, not Row: the name and the matched keyword together can exceed one
      // line on a narrow screen at a large text scale, and this sits on a form
      // that has no vertical room to spare for an overflow warning.
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          const Icon(Icons.lightbulb_outline_rounded,
              size: 16, color: AppTheme.textSecondary),
          Text(
            // The keyword is the whole point. "Suggested: Food" is a guess the
            // inspector has to take on trust; naming the word it matched lets
            // them judge it in a second, which is what D6 means by explainable.
            // The category name goes in the sentence rather than on the button
            // so it is free to wrap — one of these names is 61 characters.
            'Suggested: ${option.category.name} — matched “$keyword”',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: '.SF Pro Text',
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          OutlinedButton(
            onPressed: onAccept,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              minimumSize: const Size(0, 32),
              visualDensity: VisualDensity.compact,
              side: const BorderSide(color: AppTheme.border),
            ),
            child: const Text(
              'Use suggestion',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
