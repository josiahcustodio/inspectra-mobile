import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../data/models/checklist_template.dart';
import '../../data/models/establishment.dart';
import '../../data/models/inspection_log.dart';
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

  final TextEditingController _inspectorNameController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _inspectorNameController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _templates = OfflineService.getLocalTemplatesByCategory(
        widget.establishment.category);
        
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ratingProvider = Provider.of<RatingProvider>(context, listen: false);
      ratingProvider.reset();
      ratingProvider.initWeights(_templates);
    });
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

    if (_inspectorNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an Inspector Name.')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    String finalRemarks = _remarksController.text.trim();
    if (ratingProvider.itemNotes.isNotEmpty) {
      final deficiencies = ratingProvider.itemNotes.entries
          .where((e) => e.value.trim().isNotEmpty) // Only include non-empty notes
          .map((e) {
        final t = _templates.firstWhere((t) => t.id == e.key);
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

    final log = InspectionLog(
      establishmentId: widget.establishment.id,
      inspectorName: _inspectorNameController.text.trim(),
      totalDemerits: ratingProvider.totalDemerits,
      percentageRating: (ratingProvider.score ?? 0).toDouble(),
      remarks: finalRemarks,
      photoEvidenceUrl: photoUrl,
    );

    final success = await SyncService.submitInspectionLog(log);
    setState(() {
      _isSubmitting = false;
    });

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Submitted Successfully!')));
        Navigator.pop(context); // Go back home
      }
    } else {
      // Save to offline queue
      final jsonStr = jsonEncode(log.toJson());
      await OfflineService.inspectionsQueueBox.put(log.id, jsonStr);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved offline. Will sync later.')));
        Navigator.pop(context); // Go back home even if offline
      }
    }
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
          : SingleChildScrollView(
              child: Column(
                children: [
                  Consumer<RatingProvider>(
                    builder: (context, provider, child) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        color: Theme.of(context)
                            .colorScheme
                            .secondary
                            .withValues(alpha: 0.2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              provider.score != null ? 'Score: ${provider.score}' : 'Score: N/A',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text(
                              provider.ratingLabel,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: provider.score == null 
                                    ? Colors.grey 
                                    : (provider.score! >= 90 ? Colors.green : Colors.orange),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  _buildChecklist(),
                  const Divider(height: 32, thickness: 2),

                  // ─── Inspector Details & Remarks ────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Inspector Details',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _inspectorNameController,
                          decoration: const InputDecoration(
                            labelText: 'Inspector Name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _remarksController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Remarks / Notes',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 32, thickness: 2),

                  // Photo Evidence section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Photo Evidence',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        _evidenceImage != null
                            ? Image.file(_evidenceImage!, height: 150)
                            : ElevatedButton.icon(
                                onPressed: _pickImage,
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('Take Photo'),
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submitForm,
                        child: const Text('Submit Inspection',
                            style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}
