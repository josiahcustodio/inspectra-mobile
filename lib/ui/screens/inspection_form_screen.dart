import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/category_suggester.dart';
import '../../core/rating_scale.dart';
import '../../core/sanitary_order.dart';
import '../../data/models/checklist_template.dart';
import '../../data/models/establishment.dart';
import '../../data/models/inspection_category.dart';
import '../../data/models/inspection_log.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/offline_service.dart';
import '../../data/services/sync_service.dart';
import '../../providers/rating_provider.dart';
import '../widgets/category_picker.dart';
import '../widgets/checklist_item_card.dart';
import '../widgets/establishment_banner.dart';
import '../widgets/establishment_details_card.dart';
import '../../core/theme/app_colors.dart';

class InspectionFormScreen extends StatefulWidget {
  final Establishment establishment;

  const InspectionFormScreen({super.key, required this.establishment});

  @override
  State<InspectionFormScreen> createState() => _InspectionFormScreenState();
}

class _InspectionFormScreenState extends State<InspectionFormScreen> {
  /// Every category this device knows about, with its availability already
  /// decided. Read once: the Hive boxes cannot change while this form is open,
  /// since syncData only runs at launch.
  List<CategoryOption> _categoryOptions = const [];

  /// Null until the inspector picks. The form opens with no category chosen —
  /// deliberately, because D4 moves this decision to inspection time and
  /// nothing on the establishment is allowed to make it for them.
  CategoryOption? _category;

  CategorySuggestion? _suggestion;

  /// Driven by the pick, no longer by `widget.establishment.category`.
  List<ChecklistTemplate> _templates = const [];

  /// Bumped whenever the picker's own field text has to be re-derived from
  /// [_category] rather than from whatever the inspector last did inside it.
  /// See [_onCategorySelected].
  int _pickerRevision = 0;

  final TextEditingController _remarksController = TextEditingController();

  // [REF: SO_FORM_STATE]
  // The Sanitary Order's own fields (CHO-ESD-FR-04). Only ever read when the
  // inspection found at least one defect — see SanitaryOrder.isRequiredFor.
  final TextEditingController _soNoController = TextEditingController();
  final TextEditingController _timeGivenController = TextEditingController();
  final TextEditingController _receivedByController = TextEditingController();
  // [REF: PROPOSED_CONTACT]
  // The establishment's contact address, asked on every inspection rather than
  // only when an order is issued: this is the one moment anyone is standing in
  // front of the person who knows it. The server attaches it to the
  // establishment as soon as the inspection uploads (10_auto_owner.sql).
  final TextEditingController _pointPersonController = TextEditingController();
  DateTime? _deadline;

  // [REF: SO_ISSUE_TOGGLE]
  /// Whether this inspection issues an order. Only ever consulted when the
  /// checklist has at least one Fail: no demerits, no order, no question.
  ///
  /// Defaults ON because a demerit IS the trigger — the form's premise is
  /// "the defects listed below are observed". The toggle is the escape hatch
  /// for a defect handled with a verbal warning, not a decision the inspector
  /// has to remember to make. Turning it off is visible on screen; forgetting
  /// to turn it on would not be.
  bool _issueOrder = true;

  bool _isSubmitting = false;

  // [REF: PIN_LOCATION] Current pin, kept here because widget.establishment
  // is the immutable record the screen was opened with.
  double? _lat;
  bool _pinning = false;
  bool _initialized = false;

  final ScrollController _scrollController = ScrollController();
  BannerDensity _bannerDensity = BannerDensity.full;

  @override
  void dispose() {
    _remarksController.dispose();
    _soNoController.dispose();
    _timeGivenController.dispose();
    _receivedByController.dispose();
    _pointPersonController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // From Hive, not widget.establishment: the list that opened this screen may
    // predate a pin, and a stale null would skip the replace confirmation.
    final cached = OfflineService.getEstablishmentById(widget.establishment.id) ?? widget.establishment;
    _lat = cached.latitude;
    // Prefilled so a re-inspection restates the address on record instead of
    // submitting a blank one.
    _pointPersonController.text = cached.pointPersonEmail ?? '';
    _categoryOptions = OfflineService.getLocalCategoryOptions();

    // [REF: CATEGORY_SUGGESTION_SOURCE]
    // Only selectable categories are offered to the suggester, so a rule
    // pointing at one that has no checklist on this device — or no published
    // weighting — produces no suggestion instead of one the inspector would be
    // unable to accept.
    _suggestion = CategorySuggester.suggestFor(
      widget.establishment.name,
      availableCategoryIds: _categoryOptions
          .where((o) => o.isSelectable)
          .map((o) => o.category.id),
    );

    _scrollController.addListener(_onChecklistScroll);
  }

  // [REF: BANNER_SCROLL_DENSITY]
  /// Trades banner rows for checklist rows as the inspector scrolls.
  ///
  /// Two pinned blocks are a lot to ask of a small phone: the score header
  /// below measures about 96pt once a score exists (a 48pt figure at
  /// `height: 1.0`, a ~14pt band label, and 32pt of padding — more than the
  /// 76pt the plan estimated), and it grows with the system text scale, since
  /// the score column is always its tallest child and nothing caps that text.
  /// So the banner gives ground instead, down to the business name and owner.
  /// `densityFor` only ever returns a different value after a real threshold
  /// crossing, so this rebuilds on a handful of frames per inspection rather
  /// than on every scroll tick.
  void _onChecklistScroll() {
    final next = EstablishmentBanner.densityFor(
      _scrollController.offset,
      _bannerDensity,
    );
    if (next != _bannerDensity) {
      setState(() {
        _bannerDensity = next;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Still here rather than in initState because reading a Provider needs the
    // inherited widgets in place; the _initialized guard prevents re-runs on
    // subsequent dependency changes.
    //
    // What it does has changed, though. There are no templates to init from
    // yet — a category has not been picked. But RatingProvider is a single
    // app-wide instance (main.dart), so it can still be holding the previous
    // inspection's answers and weights, and `score` would read off them.
    // Clearing on open is what makes "no category picked" an actually empty
    // form; `init` then runs on every pick.
    if (!_initialized) {
      _initialized = true;
      Provider.of<RatingProvider>(context, listen: false).reset();
    }
  }

  // [REF: CATEGORY_SWITCH]
  /// Applies a category pick, confirming first if it would throw work away.
  ///
  /// `RatingProvider.init` clears answers, notes and weights atomically, so
  /// stale state is not the hazard here — losing the inspector's work silently
  /// is. Deficiency notes count as work too: they are typed into the item
  /// cards, not into the remarks box, so they disappear with the answers.
  /// Switching before anything has been answered must not prompt, because at
  /// that point the picker is just being corrected.
  Future<void> _onCategorySelected(CategoryOption option) async {
    if (option.category.id == _category?.category.id) return;

    // D25 enforced here as well as in the picker, deliberately. A disabled
    // `DropdownMenuEntry` is a framework property of one widget; this is the
    // function that decides which checklist gets filled in. If the two ever
    // disagree, a Livestock Farm form would load 13 weight-0 items, accept all
    // 13 marks, and submit a flat 100 / Excellent for an inspection nobody
    // scored — the precise fabrication D22 refuses to commit.
    if (!option.isSelectable) {
      // Not a silent return. In the state this guards against, the picker's
      // own field has already written the category's name into itself, so
      // bailing without a word would leave it naming a form the screen is not
      // loading. Re-keying snaps the field back; the snackbar says why.
      final reason = option.unavailableLabel;
      setState(() => _pickerRevision++);
      if (reason != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${option.category.name} cannot be inspected: '
                '${reason.toLowerCase()}.'),
          ),
        );
      }
      return;
    }

    final ratingProvider = Provider.of<RatingProvider>(context, listen: false);
    if (_hasWork(ratingProvider)) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Change checklist category?'),
              content: Text(
                'Switching to ${option.category.name} clears the '
                '${ratingProvider.answers.length} item(s) you have already '
                'marked, and any deficiency notes with them.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Keep current checklist'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Switch and clear'),
                ),
              ],
            ),
          ) ??
          false;

      // Checked before either branch touches setState: the form can be popped
      // from under an open dialog, and setState on a disposed State throws.
      if (!mounted) return;

      if (!confirmed) {
        // DropdownMenu has already written the new label into its own field by
        // the time onSelected fires, so declining here would leave the picker
        // naming a category the form is not using. Rebuilding it under a new
        // key is what snaps it back to `_category`.
        setState(() => _pickerRevision++);
        return;
      }
    }

    final templates =
        OfflineService.getLocalTemplatesByCategoryId(option.category.id);

    setState(() {
      _category = option;
      _templates = templates;
      // Bumped on accept as well as on decline. DropdownMenu keeps its field
      // text in its own State, so it is only in step with `_category` when the
      // pick came from the menu — accepting the suggestion by its button would
      // otherwise leave the field reading "Choose a category" over a loaded
      // checklist.
      //
      // This re-derives the field on every path that CHANGES the category. It
      // does not cover a path that changes nothing: typing a filter and
      // tapping away leaves the typed text sitting in the field, because no
      // selection and no decline occurred. See the gap documented on
      // CategoryPicker.
      _pickerRevision++;
    });

    ratingProvider.init(templates);
  }

  // [REF: SO_FORM_SECTION]
  /// The Sanitary Order half of the form, shown only once the checklist has
  /// at least one Fail.
  ///
  /// Hidden rather than disabled when there is nothing to order: the fields
  /// below are the operative part of a legal notice, and an inspector who
  /// found no defects should never be looking at a deadline field at all.
  /// The defect table itself is not re-entered here — it is already captured
  /// per item on the checklist above, which is where the inspector was
  /// standing when they saw it.
  Widget _buildSanitaryOrderSection(RatingProvider provider) {
    final defectCount = provider.answers.values
        .where((a) => a == SanitaryOrder.failAnswer)
        .length;
    if (defectCount == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32, thickness: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.gavel_rounded,
                      size: 20, color: AppColors.fail),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Sanitary Order',
                        style:
                            Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontFamily: '.SF Pro Display',
                                  fontWeight: FontWeight.w700,
                                )),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$defectCount defect${defectCount == 1 ? '' : 's'} observed.',
                style: const TextStyle(
                  fontFamily: '.SF Pro Text',
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                value: _issueOrder,
                onChanged: (v) => setState(() => _issueOrder = v),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Issue a Sanitary Order',
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDisplay,
                  ),
                ),
                subtitle: Text(
                  _issueOrder
                      ? 'Enter the name of the owner or point person below.'
                      : 'No order will be issued for these defects.',
                  style: const TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              // Collapsed rather than disabled when no order is being issued:
              // these are the operative fields of a legal notice and have no
              // meaning without one.
              if (!_issueOrder) const SizedBox.shrink(),
              if (_issueOrder) ...[
              const SizedBox(height: 8),
              _buildOrderField(
                controller: _soNoController,
                label: 'Sanitary Order No. (optional)',
                hint: 'From the CHO booklet — leave blank if unknown',
                icon: Icons.numbers_rounded,
              ),
              const SizedBox(height: 12),
              _buildOrderField(
                controller: _timeGivenController,
                label: 'Time given for correction',
                hint: 'e.g. 7 days',
                icon: Icons.timelapse_rounded,
              ),
              const SizedBox(height: 12),
              // A picker, not a text field: the deadline is the date a
              // re-inspection becomes due, and a typo in a hand-typed date
              // moves a legal deadline.
              InkWell(
                onTap: _pickDeadline,
                borderRadius: BorderRadius.circular(16),
                child: InputDecorator(
                  decoration: _orderDecoration(
                    label: 'Deadline',
                    hint: '',
                    icon: Icons.event_rounded,
                  ),
                  child: Text(
                    _deadline == null
                        ? 'Tap to choose a date'
                        : SanitaryOrder.toDateOnly(_deadline!),
                    style: TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontSize: 15,
                      color: _deadline == null
                          ? Colors.black38
                          : AppColors.textDisplay,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildOrderField(
                controller: _receivedByController,
                label: 'Received by',
                hint: 'Name of the owner or point person',
                icon: Icons.person_outline_rounded,
              ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _orderDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
          fontFamily: '.SF Pro Text', color: AppColors.textSecondary),
      hintText: hint,
      hintStyle:
          const TextStyle(color: Colors.black38, fontFamily: '.SF Pro Text'),
      prefixIcon: Icon(icon, color: Colors.black38),
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.5,
        ),
      ),
    );
  }

  Widget _buildOrderField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontFamily: '.SF Pro Text',
        fontSize: 15,
        color: AppColors.textDisplay,
      ),
      decoration: _orderDecoration(label: label, hint: hint, icon: icon),
    );
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 7)),
      // Not before today: a deadline already past cannot be complied with,
      // and the form promises a re-inspection "after the lapse of the time
      // given".
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _submitForm() async {
    // Re-entrance defence on top of the disabled button: the button's
    // onPressed gate only takes effect after a setState has rebuilt it, so
    // a second tap racing the first one's build can still land here.
    if (_isSubmitting) return;

    final ratingProvider = Provider.of<RatingProvider>(context, listen: false);

    // Guard order is load-bearing, not tidiness. `score` returns null whenever
    // `_weights` is empty, so `isCompleted` is false both before a category is
    // picked and when the picked one resolved to no items — and its message,
    // "answer all checklist items", would blame the inspector for two
    // conditions they cannot answer their way out of. The specific reasons
    // have to be tested first.
    final picked = _category;

    // Before "pick a category", because on a device that has never completed a
    // sync there is no category to pick and telling them to pick one is a dead
    // end. The categories box is filled only by syncData, so a first launch
    // without signal leaves it empty.
    if (_categoryOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No checklist categories on this device yet. Connect to the '
              'internet once to download them, then try again.'),
        ),
      );
      return;
    }

    if (picked == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Choose the checklist category for this inspection before submitting.'),
        ),
      );
      return;
    }

    // The other half of the D25 guard above. Unreachable while the picker and
    // this screen agree; it is here so that the rule holds at the point the
    // record is written, not only at the point it is chosen.
    if (!picked.isSelectable) {
      // Tests `isSelectable`, not `unavailableLabel != null`. They are the same
      // thing today only because every reason happens to map to a label; a
      // future reason that mapped to null would disable the picker row and
      // silently pass this guard, which is the one place it must not.
      final blocked = picked.unavailableLabel ?? 'its checklist cannot be scored';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${picked.category.name} cannot be submitted: '
              '${blocked.toLowerCase()}.'),
        ),
      );
      return;
    }

    if (_templates.isEmpty) {
      // Unreachable as the code stands, and kept anyway. `_category` is only
      // ever set to a selectable option, selectable already means at least one
      // template resolved, and both counts come from the same Hive box in the
      // same screen session — syncData cannot run underneath an open form,
      // since its only entry point unmounts this screen. So the earlier
      // guards catch every route to an empty checklist today.
      //
      // It stays because what it prevents is the worst thing this screen can
      // do: a zero-item inspection satisfies `isCompleted` the moment it is
      // opened and submits as a flat 100 with no items behind it. That is one
      // refactor away from reachable, and the message names a cause the
      // inspector can act on.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'No checklist items for ${picked.category.name} on this device. '
              'Connect to the internet to download the checklists, then try again.'),
        ),
      );
      return;
    }

    if (!ratingProvider.isCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please answer all checklist items before submitting.')),
      );
      return;
    }

    // Here as well as in firstBlocker, which stops at "no defects": the address
    // is now recorded on inspections that issue no order.
    final emailBlocker = SanitaryOrder.emailBlocker(_pointPersonController.text);
    if (emailBlocker != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(emailBlocker)),
      );
      return;
    }

    // [REF: SO_DEFECT_SOURCE]
    // Built before the submit flag so the Sanitary Order is validated against
    // the EXACT rows that will be stored — the order's defect table is
    // derived from `results`, and deriving it twice from two sources is how
    // a validated order and a written one drift apart.
    final List<Map<String, dynamic>> resultsArray = [];
    for (final entry in ratingProvider.answers.entries) {
      final itemId = entry.key;
      final answer = entry.value;

      ChecklistTemplate? template;
      try {
        template = _templates.firstWhere((t) => t.id == itemId);
      } catch (_) {
        template = null;
      }

      resultsArray.add({
        'checklist_item_id': itemId,
        'item_name': template?.item ?? itemId,
        'sub_category': template?.subCategory ?? '',
        'weight': template?.weight ?? 0,
        'answer': answer,
        'note': ratingProvider.itemNotes[itemId] ?? '',
        // The right-hand column of the order's table. Written for every row,
        // not just failures: an empty string on a Pass reads the same as the
        // blank it is, and a conditional key would make every consumer test
        // for its presence.
        'correction': ratingProvider.itemCorrections[itemId] ?? '',
        // The item's extra inputs, keyed by field label so the row reads
        // without the template (see ChecklistField). Empty on plain items.
        'values': ratingProvider.itemValues[itemId] ?? const {},
      });
    }

    // Demerits make an order POSSIBLE; the toggle decides whether one is
    // actually issued. Both have to hold.
    final defects = SanitaryOrder.defectsFrom(resultsArray);
    final issuesOrder = defects.isNotEmpty && _issueOrder;

    // Claimed before the first await so a double-tap cannot mint two rows;
    // the guard at the top of this method reads the same flag.
    setState(() => _isSubmitting = true);

    // One call, one rule: everything that makes the order issuable lives in
    // SanitaryOrder.firstBlocker, so the screen cannot enforce a different
    // document than the module describes.
    // The per-defect note and correction are required on every submission;
    // the empty defect list only skips the order's own fields (time given,
    // deadline, received-by) when no order is being issued.
    final blocker = SanitaryOrder.defectBlocker(defects) ??
        SanitaryOrder.firstBlocker(
          defects: issuesOrder ? defects : const [],
          timeGiven: _timeGivenController.text,
          deadline: _deadline,
          receivedByName: _receivedByController.text,
          pointPersonEmail: _pointPersonController.text,
        );
    if (blocker != null) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(blocker)),
      );
      return;
    }

    String finalRemarks = _remarksController.text.trim();
    if (ratingProvider.itemNotes.isNotEmpty) {
      final deficiencies = ratingProvider.itemNotes.entries
          .where((e) => e.value.trim().isNotEmpty)
          .map((e) {
        // Use orElse to avoid a StateError crash if a stale template ID is in notes
        final t = _templates.firstWhere((t) => t.id == e.key, orElse: () => ChecklistTemplate.empty(e.key));
        return "- ${t.item}: ${e.value}";
      }).join("\n");
      
      if (deficiencies.isNotEmpty) {
        if (finalRemarks.isNotEmpty) finalRemarks += "\n\n";
        finalRemarks += "Deficiencies:\n$deficiencies";
      }
    }

    final log = InspectionLog(
      establishmentId: widget.establishment.id,
      establishmentName: widget.establishment.name, // saved on the log row so any phone can display it
      // D24 — the id is the machine key, the name is the human record of which
      // checklist was administered. Neither is read back off the
      // establishment; both come from what the inspector picked.
      categoryId: picked.category.id,
      categoryName: picked.category.name,
      inspectorName: AuthService.displayName ??
          AuthService.currentUser?.email ??
          'Inspector',
      totalDemerits: ratingProvider.totalDemerits,
      percentageRating: (ratingProvider.score ?? 0).toDouble(),
      remarks: finalRemarks,
      // The order, when there was one to issue. soIssuedAt is the marker the
      // rest of the system reads — the number may legitimately stay blank
      // until CHO's booklet pattern is known.
      soIssuedAt: issuesOrder ? DateTime.now().toUtc().toIso8601String() : null,
      soNo: issuesOrder
          ? SanitaryOrder.normalizeOrderNo(_soNoController.text)
          : null,
      timeGiven: issuesOrder ? _timeGivenController.text.trim() : null,
      deadline: issuesOrder && _deadline != null
          ? SanitaryOrder.toDateOnly(_deadline!)
          : null,
      receivedByName:
          issuesOrder ? _receivedByController.text.trim() : null,
      // A proposal, not a setting: an admin approves it before it becomes the
      // establishment's address of record.
      proposedPointPersonName:
          issuesOrder ? (_receivedByController.text.trim().isEmpty
              ? null
              : _receivedByController.text.trim()) : null,
      proposedPointPersonEmail:
          SanitaryOrder.normalizeEmail(_pointPersonController.text),
      results: resultsArray,
    );

    // Local first: the queue write is the submission, so the form closes at
    // disk speed instead of waiting on a request that, offline, only returns
    // after the network stack gives up. The upload then runs behind the
    // home screen; a failure simply leaves the entry in the pending queue.
    try {
      await OfflineService.inspectionsQueueBox.put(log.id, jsonEncode(log.toJson()));
    } catch (e) {
      // Nothing was saved: keep the form open with its answers intact.
      debugPrint('Queue write failed: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save the inspection on this device. Try again.')));
      }
      return;
    }

    // Mirror the address locally, so opening this establishment again before
    // the next sync shows it.
    final cachedEst = OfflineService.getEstablishmentById(widget.establishment.id);
    if (log.proposedPointPersonEmail != null && cachedEst != null) {
      cachedEst.pointPersonEmail = log.proposedPointPersonEmail;
      // A convenience only: it must never stop the upload or the pop below.
      try {
        await cachedEst.save();
      } catch (e) {
        debugPrint('Could not mirror point person email: $e');
      }
    }

    // [REF: INSPECTION_SUBMIT_REMOTE]
    unawaited(SyncService.syncSingleInspection(log.id));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inspection saved. Uploading when online.')),
      );
      context.pop(); // Go back home
    }
  }

  // [REF: LIVE_SCORE_HEADER]
  Widget _buildStickyScoreHeader() {
    return Consumer<RatingProvider>(
      builder: (context, provider, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.background, // Matte off-white
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(25),
                blurRadius: 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Premium Medal Icon
              Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.bookmark_rounded, color: AppColors.textDisplay, size: 36), // Deep Navy Ribbon
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Icon(Icons.star_rounded, color: Colors.amber.shade500, size: 24), // Matte Gold Star
                  ),
                ],
              ),
              const SizedBox(width: 12),
              const Text(
                'Score:',
                style: TextStyle(
                  fontFamily: '.SF Pro Display',
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textDisplay,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              if (provider.score == null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'N/A',
                      style: TextStyle(
                        fontFamily: '.SF Pro Display',
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textDisplay,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Awaiting Scoring',
                      style: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                )
              else
                // [REF: RATING_SCALE] the live score carries its band so the
                // inspector sees the same label the dashboard will show.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${provider.score}',
                      style: TextStyle(
                        fontFamily: '.SF Pro Display',
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: RatingScale.colorOf(provider.score),
                        height: 1.0,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      provider.ratingLabel,
                      style: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: RatingScale.colorOf(provider.score),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  // [REF: CHECKLIST_RENDER]
  Widget _buildChecklist() {
    // Four empty states, deliberately worded apart, because the wrong one is
    // actively misleading. "No checklists found for this category" is a report
    // about a chosen category; showing it before anything is chosen reads as a
    // form that failed to load. And any copy telling the inspector to pick a
    // category is an instruction they cannot follow when the picker has no
    // rows, or no selectable ones — so those two states get their own text,
    // naming the cause and the fix. The last branch is unreachable today (see
    // the submit guards) and is kept for the same reason they are.
    if (_categoryOptions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(
          child: Text(
            'No checklist categories on this device yet.\n'
            'Connect to the internet once to download them.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    // Reachable by exactly the partial sync [REF: TEMPLATE_LOOKUP_ID_BRIDGE]
    // describes: the categories fetch lands, the establishments loop throws,
    // and the templates are never written. Every row then carries its own
    // "no checklist items on this device", but the body must not still be
    // telling the inspector to choose one of them.
    if (_categoryOptions.every((o) => !o.isSelectable)) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(
          child: Text(
            'None of the categories on this device has a checklist yet.\n'
            'Connect to the internet to finish downloading them.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    if (_category == null) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(
          child: Text(
            'Choose a checklist category above to load its items.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    if (_templates.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(
          child: Text(
            'No checklists found for this category.',
            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    // Group by sub_category
    final Map<String, List<ChecklistTemplate>> grouped = {};
    for (var t in _templates) {
      grouped.putIfAbsent(t.subCategory, () => []).add(t);
    }

    return Column(
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.key.isNotEmpty && entry.key != 'General')
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                child: Text(
                  entry.key,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ...entry.value.map((item) => _buildChecklistItem(item)),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildChecklistItem(ChecklistTemplate item) {
    // Keyed by item id so that switching category replaces the cards rather
    // than re-using their elements by position.
    //
    // Not for the deficiency notes: that TextFormField is mounted only while
    // the item reads Fail, and `RatingProvider.init` clears every answer in
    // the same frame as the new templates, so on the first build after a
    // switch no card has one. It is for the animations — the card's
    // `AnimatedContainer` and the notes `AnimatedSize` interpolate from
    // whatever their element last held, so re-used elements would animate a
    // new checklist's rows out of the old one's selection states.
    return ChecklistItemCard(key: ValueKey(item.id), item: item);
  }

  // [REF: PIN_LOCATION]
  Future<void> _pinLocation() async {
    final perm = await Permission.locationWhenInUse.request();
    if (!mounted) return;
    if (!perm.isGranted) {
      _gpsAdvice('Location permission is needed to pin this establishment.');
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) _gpsAdvice('Location is turned off. Turn on GPS, then try again.');
      return;
    }
    setState(() => _pinning = true);
    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 25),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _pinning = false);
        _gpsAdvice('No GPS fix. Move to an open space, away from roofs and walls, then try again.');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _pinning = false);
    final acc = pos.accuracy.round();

    if (acc > 100) {
      final useAnyway = await _confirm(
        'Weak GPS signal',
        'The fix is only accurate to about $acc m. Move to an open space and try again, or use it anyway.',
        'Use anyway',
      );
      if (useAnyway != true || !mounted) return;
    }
    if (_lat != null) {
      final replace = await _confirm(
        'Replace pinned location?',
        'This establishment already has a map pin. Replace it with your current position (±$acc m)?',
        'Replace',
      );
      if (replace != true || !mounted) return;
    }

    await OfflineService.pinLocation(widget.establishment.id, pos.latitude, pos.longitude);
    if (!mounted) return;
    setState(() => _lat = pos.latitude);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Location pinned (±$acc m). It now shows on the map.')),
    );
  }

  void _gpsAdvice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool?> _confirm(String title, String body, String yes) => showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(d).pop(true), child: Text(yes)),
          ],
        ),
      );

  /// Anything the inspector would lose by leaving or switching checklist.
  static bool _hasWork(RatingProvider p) =>
      p.answers.isNotEmpty || p.itemNotes.values.any((n) => n.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    // Drives [REF: BANNER_KEYBOARD_YIELD] below. This has to be read HERE,
    // from the State's own context above the Scaffold: Scaffold wraps its body
    // in a MediaQuery with removeViewInsets(removeBottom: true) whenever
    // resizeToAvoidBottomInset is on, so the same call from inside the body
    // — a Builder, a LayoutBuilder, or the banner itself — reads a constant
    // zero. It would fail silently: no warning, no exception, just the clipped
    // checklist this guard exists to prevent.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    // canPop is always false so the check runs at back-press time without
    // subscribing the whole screen to every answer tap.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final rating = Provider.of<RatingProvider>(context, listen: false);
        if (!_hasWork(rating)) {
          Navigator.of(context).pop();
          return;
        }
        final leave = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Discard this inspection?'),
            content: Text(
              '${rating.answers.length} marked item(s) and any deficiency '
              'notes will be lost.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Keep editing')),
              TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Discard')),
            ],
          ),
        );
        if (leave == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        // Deliberately duplicates the banner's business name, because this
        // is the copy that cannot be taken away: the app bar sits outside the
        // body Column, so unlike the banner it costs the checklist no vertical
        // space and never yields to the keyboard. When the banner withdraws
        // ([REF: BANNER_KEYBOARD_YIELD]) this is what still names the business
        // the inspector is scoring. Truncating on a narrow screen is an
        // acceptable price for a backstop.
        title: Text(
          widget.establishment.name.isEmpty
              ? 'Inspection'
              : widget.establishment.name,
        ),
      ),
      body: _isSubmitting
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Both of these sit outside the scroll view, which is what pins
                // them. A CustomScrollView with two SliverPersistentHeaders
                // would have given the shrink for free, but every
                // SliverPersistentHeaderDelegate has to declare minExtent and
                // maxExtent in logical pixels — and neither of these blocks has
                // a knowable height, since both grow with MediaQuery.textScaler
                // and the banner also grows with how far an address wraps.
                // Guessed extents would clip at large text scales.
                //
                // [REF: BANNER_KEYBOARD_YIELD]
                // What this Column cannot do is overflow gracefully: the two
                // pinned children are inflexible, so once they exceed the body
                // the Expanded below is clamped to zero and the checklist is
                // clipped outright. That is reachable — 320x568 at text scale
                // 2.0 with the keyboard up leaves about 276pt against roughly
                // 285pt of chrome. The banner withdraws completely for the
                // duration instead of shrinking, which hands back the ~118pt
                // the form had before it existed and keeps the focused field
                // scrollable into view.
                //
                // Note this fires for ANY keyboard, not just the remarks field
                // at the bottom: marking an item FAIL reveals a required
                // deficiency-notes field inline, mid-checklist, so the keyboard
                // genuinely does open while scoring. That is why the app bar
                // above keeps its own copy of the business name — it is what
                // satisfies the never-lose-the-name rule during exactly this
                // window.
                if (!keyboardOpen)
                  EstablishmentBanner(
                    establishment: widget.establishment,
                    density: _bannerDensity,
                  ),
                _buildStickyScoreHeader(), // Pinned Header
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      children: [
                        const SizedBox(height: 16), // Padding before checklist starts

                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: OutlinedButton.icon(
                            onPressed: _pinning ? null : _pinLocation,
                            icon: _pinning
                                ? const SizedBox(
                                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : Icon(_lat == null
                                    ? Icons.add_location_alt_outlined
                                    : Icons.edit_location_alt_outlined),
                            label: Text(_pinning
                                ? 'Getting GPS fix…'
                                : _lat == null
                                    ? 'Pin GPS location here'
                                    : 'Update pinned location'),
                          ),
                        ),
                        EstablishmentDetailsCard(
                          establishment: widget.establishment,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildOrderField(
                                controller: _pointPersonController,
                                label: 'Owner / point person email (optional)',
                                hint: 'name@gmail.com',
                                icon: Icons.alternate_email_rounded,
                                keyboardType: TextInputType.emailAddress,
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Saved to this establishment. The owner signs in '
                                'with this address to view results.',
                                style: TextStyle(
                                  fontFamily: '.SF Pro Text',
                                  fontSize: 11,
                                  height: 1.4,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // [REF: CATEGORY_PICKER_PLACEMENT]
                        // Inside the scroll view, not in the pinned Column
                        // above. [REF: BANNER_KEYBOARD_YIELD] already has the
                        // two pinned blocks within ~9pt of clipping the
                        // checklist at 320x568 / scale 2.0, and the category is
                        // chosen once at the start — pinning it would spend
                        // permanent height on a transient decision. The app bar
                        // and banner keep naming the establishment, and the
                        // chosen category is restated on the submitted log.
                        //
                        // The filter field opens the keyboard on focus, which
                        // triggers the banner yield. That works in the picker's
                        // favour: the ~118pt the banner hands back is reclaimed
                        // exactly while the menu needs room. The menu itself is
                        // an Overlay route, so it is never clipped by this
                        // Column either way.
                        CategoryPicker(
                          // Rebuilt from scratch when a pick is declined, so
                          // DropdownMenu's internal field text cannot drift
                          // away from `_category`. See [REF: CATEGORY_SWITCH].
                          key: ValueKey('category-picker-$_pickerRevision'),
                          options: _categoryOptions,
                          selectedCategoryId: _category?.category.id,
                          suggestion: _suggestion,
                          onSelected: _onCategorySelected,
                        ),
                        const SizedBox(height: 8),

                        _buildChecklist(),
                  const Divider(height: 32, thickness: 2),

                  // ─── Remarks / Notes ────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Remarks / Notes',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontFamily: '.SF Pro Display',
                                  fontWeight: FontWeight.w700,
                                )),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _remarksController,
                          maxLines: 4,
                          style: const TextStyle(
                            fontFamily: '.SF Pro Text',
                            fontSize: 15,
                            color: AppColors.textDisplay,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Add any final observations...',
                            hintStyle: const TextStyle(
                              color: Colors.black38,
                              fontFamily: '.SF Pro Text',
                            ),
                            filled: true,
                            fillColor: AppColors.background,
                            contentPadding: const EdgeInsets.all(16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // A Consumer of its own so answering the last checklist item
                  // reveals the section without rebuilding the whole form.
                  Consumer<RatingProvider>(
                    builder: (context, provider, _) =>
                        _buildSanitaryOrderSection(provider),
                  ),
                  const SizedBox(height: 48), // Padding before bottom nav
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).padding.bottom + 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _submitForm,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.textDisplay, // Deep Navy / Charcoal
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text(
                  'Submit Inspection',
                  style: TextStyle(
                    fontFamily: '.SF Pro Display',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
        ),
      ),
      ),
    );
  }
}
