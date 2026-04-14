import 'package:flutter/material.dart';
import '../../data/models/establishment.dart';
import '../../data/services/sync_service.dart';

class AddEstablishmentScreen extends StatefulWidget {
  const AddEstablishmentScreen({super.key});

  @override
  State<AddEstablishmentScreen> createState() => _AddEstablishmentScreenState();
}

class _AddEstablishmentScreenState extends State<AddEstablishmentScreen> {
  final _formKey = GlobalKey<FormState>();

  List<String> _categories = [];
  String? _category;
  bool _categoriesLoading = true;

  final _nameController = TextEditingController();
  final _ownerController = TextEditingController();
  final _addressController = TextEditingController();
  final _personnelController = TextEditingController();
  final _personnelHcController = TextEditingController();
  final _sanitaryPermitController = TextEditingController();
  final _controlNoController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final cats = await SyncService.fetchCategories();
    if (mounted) {
      setState(() {
        _categories = cats;
        _category = cats.isNotEmpty ? cats.first : null;
        _categoriesLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ownerController.dispose();
    _addressController.dispose();
    _personnelController.dispose();
    _personnelHcController.dispose();
    _sanitaryPermitController.dispose();
    _controlNoController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a Type of Establishment.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final newEstablishment = Establishment(
      id: '',
      name: _nameController.text.trim(),
      category: _category!,
      address: _addressController.text.trim(),
      ownerName: _ownerController.text.trim(),
      personnelCount: int.tryParse(_personnelController.text) ?? 0,
      personnelWithHc: int.tryParse(_personnelHcController.text) ?? 0,
      sanitaryPermitNo: _sanitaryPermitController.text.trim(),
      controlNo: _controlNoController.text.trim(),
    );

    final success = await SyncService.insertEstablishment(newEstablishment);

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Establishment Added Successfully!')),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to add establishment. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Establishment'),
      ),
      body: (_isSubmitting)
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Establishment Details',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Dynamic Category Dropdown ──────────────────────────
                    _categoriesLoading
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : DropdownButtonFormField<String>(
                            initialValue: _category,
                            decoration: InputDecoration(
                              labelText: 'Type of Establishment *',
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: Icon(Icons.business,
                                  color: theme.colorScheme.primary),
                            ),
                            items: _categories.map((cat) {
                              return DropdownMenuItem(
                                  value: cat, child: Text(cat));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _category = val);
                            },
                            validator: (val) =>
                                val == null ? 'Please select a type' : null,
                          ),
                    const SizedBox(height: 16),

                    // ── Name ──────────────────────────────────────────────
                    _buildTextField(
                      'Name of Establishment',
                      _nameController,
                      icon: Icons.store,
                      isRequired: true,
                    ),
                    const SizedBox(height: 16),

                    // ── Owner ─────────────────────────────────────────────
                    _buildTextField(
                      'Owner / Manager / Representative',
                      _ownerController,
                      icon: Icons.person,
                      isRequired: true,
                    ),
                    const SizedBox(height: 16),

                    // ── Address ───────────────────────────────────────────
                    _buildTextField(
                      'Address',
                      _addressController,
                      icon: Icons.location_on,
                      isRequired: true,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),

                    // ── Personnel Count Row ───────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            'No. of Personnel',
                            _personnelController,
                            icon: Icons.group,
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            'No. with Health Cert',
                            _personnelHcController,
                            icon: Icons.health_and_safety,
                            isNumber: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Auto Date ─────────────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withOpacity(0.4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          Text(
                            'Date of Inspection: ${DateTime.now().toLocal().toString().split(' ')[0]}  (Auto)',
                            style: TextStyle(
                                color: Colors.grey.shade700,
                                fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Permits Row ───────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            'Sanitary Permit No.',
                            _sanitaryPermitController,
                            icon: Icons.article,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            'Control No.',
                            _controlNoController,
                            icon: Icons.tag,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // ── Submit ────────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: _submitForm,
                        icon: const Icon(Icons.save),
                        label: const Text(
                          'Save Establishment',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    IconData? icon,
    bool isRequired = false,
    bool isNumber = false,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label + (isRequired ? ' *' : ''),
        prefixIcon: icon != null
            ? Icon(icon, color: Theme.of(context).colorScheme.primary)
            : null,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: (value) {
        if (isRequired && (value == null || value.trim().isEmpty)) {
          return 'This field is required';
        }
        return null;
      },
    );
  }
}
