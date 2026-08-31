import 'package:go_router/go_router.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/establishment.dart';
import '../../data/services/offline_service.dart';
import '../../data/services/sync_service.dart';
import 'package:uuid/uuid.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../widgets/animations/squishy_button.dart';
import '../widgets/animations/fade_slide_entrance.dart';

class AddEstablishmentScreen extends StatefulWidget {
  final Establishment? establishment;
  const AddEstablishmentScreen({super.key, this.establishment});

  @override
  State<AddEstablishmentScreen> createState() => _AddEstablishmentScreenState();
}

class _AddEstablishmentScreenState extends State<AddEstablishmentScreen> {
  // globalkey
  final _formKey = GlobalKey<FormState>();

  List<String> _categories = [];
  Map<String, String> _categoryIdByName = {};
  String? _category;
  bool _categoriesLoading = true;

  final _nameController = TextEditingController();
  final _ownerController = TextEditingController();
  final _streetController = TextEditingController();
  final _personnelController = TextEditingController();
  final _personnelHcController = TextEditingController();
  final _sanitaryPermitController = TextEditingController();
  final _controlNoController = TextEditingController();

  bool _isSubmitting = false;
  bool _isDeleting = false;

  final String _province = "Batangas";
  final String _city = "Batangas City";
  List<String> _barangays = [];
  String? _selectedBarangay;
  bool _barangaysLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadBarangays();
    _prefillData();
  }

  void _prefillData() {
    if (widget.establishment != null) {
      final est = widget.establishment!;
      _nameController.text = est.name;
      _ownerController.text = est.ownerName;
      _personnelController.text = est.personnelCount.toString();
      _personnelHcController.text = est.personnelWithHc.toString();
      _sanitaryPermitController.text = est.sanitaryPermitNo;
      _controlNoController.text = est.controlNo;

      try {
        final Map<String, dynamic> addr = jsonDecode(est.address);
        _selectedBarangay = addr['barangay'];
        _streetController.text = addr['street'] ?? '';
      } catch (_) {
        _streetController.text = est.address == 'N/A' ? '' : est.address;
      }
    }
  }

  Future<void> _loadBarangays() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/data/batangas_psgc.json');
      final data = jsonDecode(jsonString);
      if (mounted) {
        setState(() {
          _barangays = List<String>.from(data['barangays'] ?? []);
          _barangaysLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load barangays: $e');
      if (mounted) {
        setState(() => _barangaysLoading = false);
      }
    }
  }

  Future<void> _loadCategories() async {
    final cats = await SyncService.fetchCategories();
    if (mounted) {
      setState(() {
        _categories = cats.map((c) => c['name']!).toList();
        _categoryIdByName = {for (final c in cats) c['name']!: c['id']!};
        _category = widget.establishment != null && _categories.contains(widget.establishment!.category)
            ? widget.establishment!.category
            : (_categories.isNotEmpty ? _categories.first : null);
        _categoriesLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ownerController.dispose();
    _streetController.dispose();
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
        // snackbar
        SnackBar(
          content: const Text('Please select a Type of Establishment.'),
          backgroundColor: Colors.redAccent.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_selectedBarangay == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a Barangay.'),
          backgroundColor: Colors.redAccent.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final String street = _streetController.text.trim();
    final addressMap = {
      "province": _province,
      "city": _city,
      "barangay": _selectedBarangay,
      "street": street,
      "fullAddress": street.isEmpty ? "$_selectedBarangay, $_city, $_province" : "$street, $_selectedBarangay, $_city, $_province",
    };

    // Prefer the freshly-loaded category's real Firestore doc id; fall back
    // to whatever id the establishment already had if the live category
    // list doesn't contain a match (e.g. renamed/deleted category), so an
    // edit never silently wipes out a previously-valid category_id.
    final String? resolvedCategoryId =
        _categoryIdByName[_category] ?? widget.establishment?.categoryId;

    final newEstablishment = Establishment(
      id: widget.establishment?.id.isNotEmpty == true ? widget.establishment!.id : const Uuid().v4(),
      name: _nameController.text.trim(),
      category: _category!,
      address: jsonEncode(addressMap),
      ownerName: _ownerController.text.trim(),
      personnelCount: int.tryParse(_personnelController.text) ?? 0,
      personnelWithHc: int.tryParse(_personnelHcController.text) ?? 0,
      sanitaryPermitNo: _sanitaryPermitController.text.trim(),
      controlNo: _controlNoController.text.trim(),
      barangay: _selectedBarangay ?? 'Unknown',
      categoryId: resolvedCategoryId,
    );

    bool success = false;
    if (widget.establishment != null) {
      success = await SyncService.updateEstablishment(newEstablishment);
    } else {
      final newDocId = await SyncService.insertEstablishment(newEstablishment);
      success = newDocId != null;
    }

    if (!success) {
      newEstablishment.isSynced = false;
    }
    
    // Always save locally so the user doesn't lose data
    await OfflineService.updateEstablishment(newEstablishment);

    if (mounted) {
      setState(() => _isSubmitting = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success 
            ? 'Establishment ${widget.establishment != null ? 'Updated' : 'Added'} Successfully!' 
            : 'Saved offline. Will sync later.'),
          backgroundColor: success ? Colors.green.shade700 : Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop(true);
    }
  }

  Future<void> _deleteEstablishment() async {
    final est = widget.establishment;
    if (est == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Establishment'),
        content: Text('Delete "${est.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);

    // Deletion has no offline queue (unlike create/update, which retry via
    // isSynced) — deleting the local copy while the remote delete failed
    // would just reappear on the next full sync. Require the remote delete
    // to succeed before touching the local Hive copy.
    final success = await SyncService.deleteEstablishment(est.id);
    if (!success) {
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete — check your connection and try again.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    await OfflineService.deleteEstablishment(est.id);

    if (mounted) {
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Establishment deleted.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop(true);
    }
  }

  Widget _staggeredItem(int index, Widget child) {
    return FadeSlideEntrance(
      delay: Duration(milliseconds: 100 + (index * 50)),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int _idx = 0;

    return Theme(
      data: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0D9488),
          secondary: Color(0xFF10B981),
          surface: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
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
            borderSide: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
          labelStyle: const TextStyle(color: Color(0xFF64748B)),
          hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
      ),
      // scaffold
      child: Scaffold(
        extendBodyBehindAppBar: true,
        // appbar
        appBar: AppBar(
          title: Text(widget.establishment != null ? 'Edit Establishment' : 'Add Establishment',
              style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          actions: widget.establishment != null
              ? [
                  IconButton(
                    icon: _isDeleting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                          )
                        : const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: _isDeleting ? null : _deleteEstablishment,
                  ),
                ]
              : null,
        ),
        body: Stack(
          children: [
            // Background Dynamic Shapes
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -100,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                ),
              ),
            ),
            // Global Background Blur (Glassmorphism)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: Container(color: Colors.transparent),
              ),
            ),

            // Main Content
            SafeArea(
              child: IgnorePointer(
                ignoring: _isSubmitting,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  // form
                  child: Form(
                    key: _formKey,
                    // column
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _staggeredItem(
                          _idx++,
                          const Text(
                            'Establishment Details',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        
                        // Category Dropdown
                        _staggeredItem(
                          _idx++,
                          _categoriesLoading
                              ? Container(
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                  ),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0D9488)),
                                    ),
                                  ),
                                )
                              : DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: _category,
                                  dropdownColor: Colors.white,
                                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF0D9488)),
                                  decoration: const InputDecoration(
                                    labelText: 'Type of Establishment *',
                                    prefixIcon: Icon(Icons.business, color: Color(0xFF0D9488)),
                                  ),
                                  items: _categories.map((cat) {
                                    return DropdownMenuItem(value: cat, child: Text(cat, style: const TextStyle(color: Color(0xFF0F172A))));
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _category = val);
                                  },
                                  validator: (val) => val == null ? 'Please select a type' : null,
                                ),
                        ),

                        _staggeredItem(_idx++, _buildTextField('Name of Establishment', _nameController, icon: Icons.store, isRequired: true)),
                        _staggeredItem(_idx++, _buildTextField('Owner / Manager / Representative', _ownerController, icon: Icons.person, isRequired: true)),
                        
                        // Address Details
                        _staggeredItem(
                          _idx++,
                          const Padding(
                            padding: EdgeInsets.only(top: 8.0, bottom: 4.0),
                            child: Text(
                              'Address Location',
                              style: TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ),

                        // Locked Province & City
                        _staggeredItem(
                          _idx++,
                          Row(
                            children: [
                              Expanded(child: _buildLockedField('Province', _province, Icons.map)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildLockedField('City', _city, Icons.location_city)),
                            ],
                          ),
                        ),

                        // Dynamic Barangay Dropdown
                        _staggeredItem(
                          _idx++,
                          _barangaysLoading
                              ? Container(
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                  ),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0D9488)),
                                    ),
                                  ),
                                )
                              : DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value: _selectedBarangay != null && _barangays.contains(_selectedBarangay) ? _selectedBarangay : null,
                                  dropdownColor: Colors.white,
                                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF0D9488)),
                                  decoration: const InputDecoration(
                                    labelText: 'Barangay *',
                                    prefixIcon: Icon(Icons.location_on, color: Color(0xFF0D9488)),
                                  ),
                                  items: _barangays.map((b) {
                                    return DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(color: Color(0xFF0F172A))));
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedBarangay = val);
                                  },
                                  validator: (val) => val == null ? 'Please select a barangay' : null,
                                ),
                        ),
                        
                        _staggeredItem(_idx++, _buildTextField('Street / House No. / Landmark', _streetController, icon: Icons.edit_road, isRequired: false, maxLines: 2)),

                        _staggeredItem(
                          _idx++,
                          // row
                          Row(
                            children: [
                              Expanded(child: _buildTextField('No. of Personnel', _personnelController, icon: Icons.group, isNumber: true)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildTextField('No. with Health Cert', _personnelHcController, icon: Icons.health_and_safety, isNumber: true)),
                            ],
                          ),
                        ),

                        // Auto Date
                        _staggeredItem(
                          _idx++,
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: Row(
                              children: [
                                // icon
                                const Icon(Icons.calendar_today, size: 20, color: Color(0xFF0D9488)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Date of Inspection: ${DateTime.now().toLocal().toString().split(' ')[0]}',
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text('Auto', style: TextStyle(color: Color(0xFF0D9488), fontSize: 12, fontWeight: FontWeight.bold)),
                                )
                              ],
                            ),
                          ),
                        ),

                        _staggeredItem(
                          _idx++,
                          Row(
                            children: [
                              Expanded(child: _buildTextField('Sanitary Permit No.', _sanitaryPermitController, icon: Icons.article)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildTextField('Control No.', _controlNoController, icon: Icons.tag)),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Submit Button
                        _staggeredItem(
                          _idx++,
                          SquishyButton(
                            onPressed: _submitForm,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: double.infinity,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  colors: _isSubmitting 
                                      ? [Colors.grey.shade400, Colors.grey.shade300]
                                      : [const Color(0xFF0D9488), const Color(0xFF10B981)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: _isSubmitting ? [] : [
                                  BoxShadow(
                                    color: const Color(0xFF0D9488).withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: _isSubmitting
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.save, color: Colors.white),
                                          SizedBox(width: 8),
                                          Text(
                                            widget.establishment != null ? 'Update Establishment' : 'Save Establishment',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                        
                        if (widget.establishment != null) ...[
                          const SizedBox(height: 48),
                          _staggeredItem(
                            _idx++,
                            Center(
                              child: Column(
                                children: [
                                  const Text(
                                    'Establishment QR Code',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(24),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.05),
                                          blurRadius: 20,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: QrImageView(
                                      data: widget.establishment!.id,
                                      version: QrVersions.auto,
                                      size: 200.0,
                                      backgroundColor: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 56,
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        context.push('/inspection', extra: widget.establishment!);
                                      },
                                      icon: const Icon(Icons.assignment),
                                      label: const Text(
                                        'Inspect Establishment',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF0D9488),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        elevation: 0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
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
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: false) : TextInputType.text,
      inputFormatters: isNumber
          ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)]
          : null,
      maxLines: maxLines,
      style: const TextStyle(color: Color(0xFF0F172A)),
      decoration: InputDecoration(
        labelText: label + (isRequired ? ' *' : ''),
        prefixIcon: icon != null ? Icon(icon, color: const Color(0xFF0D9488)) : null,
      ),
      validator: (value) {
        if (isRequired && (value == null || value.trim().isEmpty)) {
          return 'This field is required';
        }
        return null;
      },
    );
  }

  Widget _buildLockedField(String label, String value, IconData icon) {
    return TextFormField(
      initialValue: value,
      enabled: false,
      style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF94A3B8)),
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
      ),
    );
  }
}
