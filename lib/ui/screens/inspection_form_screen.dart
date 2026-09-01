import 'package:go_router/go_router.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../data/models/checklist_template.dart';
import '../../data/models/establishment.dart';
import '../../data/models/inspection_log.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/offline_service.dart';
import '../../data/services/sync_service.dart';
import '../../providers/rating_provider.dart';
import '../widgets/checklist_item_card.dart';

class InspectionFormScreen extends StatefulWidget {
  final Establishment establishment;

  const InspectionFormScreen({super.key, required this.establishment});

  @override
  State<InspectionFormScreen> createState() => _InspectionFormScreenState();
}

class _InspectionFormScreenState extends State<InspectionFormScreen> {
  late List<ChecklistTemplate> _templates;
  File? _evidenceImage;
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _remarksController = TextEditingController();

  bool _isSubmitting = false;
  bool _initialized = false;

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _templates = OfflineService.getLocalTemplatesByCategory(
        widget.establishment.category);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize atomically here — safe to read Provider, runs before first build.
    // The _initialized guard prevents re-runs on subsequent dependency changes.
    if (!_initialized) {
      _initialized = true;
      Provider.of<RatingProvider>(context, listen: false).init(_templates);
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      setState(() {
        _evidenceImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _submitForm() async {
    final ratingProvider = Provider.of<RatingProvider>(context, listen: false);

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

    // Simulate uploading photo
    String? photoUrl;
    if (_evidenceImage != null) {
      final fileName =
          '${widget.establishment.id}_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      photoUrl = await SyncService.uploadImage(_evidenceImage!, fileName);
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
      inspectorName: AuthService.currentUser?.displayName ??
          AuthService.currentUser?.email ??
          'Inspector',
      totalDemerits: ratingProvider.totalDemerits,
      percentageRating: (ratingProvider.score ?? 0).toDouble(),
      remarks: finalRemarks,
      photoEvidenceUrl: photoUrl,
      results: resultsArray,
    );

    final success = await SyncService.submitInspectionLog(log);

    // Results are now embedded in log.toJson() directly.

    setState(() {
      _isSubmitting = false;
    });

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Submitted Successfully!')));
        context.pop(); // Go back home
      }
    } else {
      // Save to offline queue
      final jsonStr = jsonEncode(log.toJson());
      await OfflineService.inspectionsQueueBox.put(log.id, jsonStr);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved offline. Will sync later.')));
        context.pop(); // Go back home even if offline
      }
    }
  }

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
                Text(
                  '${provider.score}',
                  style: const TextStyle(
                    fontFamily: '.SF Pro Display',
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    height: 1.0,
                    letterSpacing: -1.5,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChecklist() {
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
    return ChecklistItemCard(item: item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('Inspect: ${widget.establishment.name}'),
      ),
      body: _isSubmitting
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildStickyScoreHeader(), // Pinned Header
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 16), // Padding before checklist starts
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
