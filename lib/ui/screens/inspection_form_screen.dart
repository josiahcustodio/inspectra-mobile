import 'package:go_router/go_router.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/category_suggester.dart';
import '../../core/rating_scale.dart';
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

  File? _evidenceImage;
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _remarksController = TextEditingController();

  bool _isSubmitting = false;
  bool _initialized = false;

  final ScrollController _scrollController = ScrollController();
  BannerDensity _bannerDensity = BannerDensity.full;

  @override
  void dispose() {
    _remarksController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
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
    final hasWork = ratingProvider.answers.isNotEmpty ||
        ratingProvider.itemNotes.values.any((n) => n.trim().isNotEmpty);

    if (hasWork) {
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

  // [REF: PHOTO_EVIDENCE_PICKER]
  /// Captures one evidence photo and compresses it on the device before it ever
  /// touches the network.
  ///
  /// A modern phone camera produces a 4–12 MB JPEG. Inspectors work on mobile
  /// data in the field, and every one of those megabytes is paid for twice —
  /// once on their connection, once in Firebase Storage egress. 1600px at 70%
  /// quality is still far more detail than a sanitary deficiency photo needs
  /// and typically lands around 200–400 KB, a 10–20x reduction.
  ///
  /// image_picker does this resize/re-encode natively on the platform side, so
  /// there is no extra Dart package and no main-thread cost.
  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 70,
    );
    if (pickedFile != null) {
      setState(() {
        _evidenceImage = File(pickedFile.path);
      });
    }
  }

  // [REF: INSPECTION_SUBMIT]
  Future<void> _submitForm() async {
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

    setState(() {
      _isSubmitting = true;
    });

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

    // Try to upload the evidence photo now. If this fails (offline, or the
    // upload itself errors) photoUrl stays null and we keep the on-device path
    // instead — SyncService retries the upload when the queued inspection
    // syncs, so the photo is no longer silently lost.
    String? photoUrl;
    if (_evidenceImage != null) {
      photoUrl = await SyncService.uploadImage(
        _evidenceImage!,
        SyncService.evidencePath(widget.establishment.id),
      );
    }

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
      });
    }

    final log = InspectionLog(
      establishmentId: widget.establishment.id,
      establishmentName: widget.establishment.name, // saved to Firestore so any phone can display it
      // D24 — the id is the machine key, the name is the human record of which
      // checklist was administered. Neither is read back off the
      // establishment; both come from what the inspector picked.
      categoryId: picked.category.id,
      categoryName: picked.category.name,
      inspectorName: AuthService.currentUser?.displayName ??
          AuthService.currentUser?.email ??
          'Inspector',
      totalDemerits: ratingProvider.totalDemerits,
      percentageRating: (ratingProvider.score ?? 0).toDouble(),
      remarks: finalRemarks,
      photoEvidenceUrl: photoUrl,
      // Only stage the local path when the upload did not already succeed.
      localPhotoPath:
          (photoUrl == null && _evidenceImage != null) ? _evidenceImage!.path : null,
      results: resultsArray,
    );

    final success = await SyncService.submitInspectionLog(log);

    // Results are embedded in log.toJson() directly.

    // A photo that was captured but not uploaded still counts as unfinished
    // work, even when the Firestore write itself succeeded (Storage can fail
    // while Firestore is reachable). Re-queueing is safe and cheap: the sync
    // pass writes to the same document id with merge:true, so the retry
    // uploads the photo and patches the URL in without duplicating anything.
    final photoStillPending = _evidenceImage != null && photoUrl == null;

    setState(() {
      _isSubmitting = false;
    });

    if (success && !photoStillPending) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Submitted Successfully!')));
        context.pop(); // Go back home
      }
      return;
    }

    // Save to the offline queue. toQueueJson keeps the on-device photo path so
    // the evidence survives until it can be uploaded.
    final jsonStr = jsonEncode(log.toQueueJson());
    await OfflineService.inspectionsQueueBox.put(log.id, jsonStr);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Submitted. Photo will upload when you have signal.'
              : 'Saved offline. Will sync later.'),
        ),
      );
      context.pop(); // Go back home even if offline
    }
  }

  // [REF: LIVE_SCORE_HEADER]
  Widget _buildStickyScoreHeader() {
    return Consumer<RatingProvider>(
      builder: (context, provider, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC), // Matte off-white
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
                  const Icon(Icons.bookmark_rounded, color: Color(0xFF0F172A), size: 36), // Deep Navy Ribbon
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
                  color: Color(0xFF0F172A),
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
                        color: Color(0xFF0F172A),
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

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
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
                            color: Color(0xFF0F172A),
                          ),
                          decoration: InputDecoration(
                            hintText: 'Add any final observations...',
                            hintStyle: const TextStyle(
                              color: Colors.black38,
                              fontFamily: '.SF Pro Text',
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.all(16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
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
                  const Divider(height: 32, thickness: 2),

                  // Photo Evidence section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Photo Evidence',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontFamily: '.SF Pro Display',
                                  fontWeight: FontWeight.w700,
                                )),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            width: double.infinity,
                            height: 160,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFCBD5E1),
                                width: 2,
                                // Note: For dashed lines, we're using a solid subtle border here
                                // to avoid extra dependencies, but keeping it light and soft.
                              ),
                            ),
                            child: _evidenceImage != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.file(_evidenceImage!, fit: BoxFit.cover),
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withAlpha(10),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Icon(Icons.camera_alt_outlined, 
                                            size: 32, 
                                            color: Theme.of(context).colorScheme.primary),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Tap to capture evidence',
                                        style: TextStyle(
                                          fontFamily: '.SF Pro Text',
                                          color: Color(0xFF64748B),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
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
            backgroundColor: const Color(0xFF0F172A), // Deep Navy / Charcoal
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
    );
  }
}
