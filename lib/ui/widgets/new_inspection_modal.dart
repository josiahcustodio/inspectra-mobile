import 'package:flutter/material.dart';
import '../../data/models/establishment.dart';
import '../../data/services/offline_service.dart';
import '../screens/add_establishment_screen.dart';
import '../screens/inspection_form_screen.dart';
import '../screens/qr_scanner_screen.dart';

class NewInspectionModal extends StatefulWidget {
  final ThemeData theme;

  const NewInspectionModal({super.key, required this.theme});

  @override
  State<NewInspectionModal> createState() => _NewInspectionModalState();
}

class _NewInspectionModalState extends State<NewInspectionModal> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Establishment> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = []);
      }
      return;
    }

    final allEst = OfflineService.getLocalEstablishments();
    final matches = allEst.where((est) {
      return est.name.toLowerCase().contains(query) ||
          est.id.toLowerCase().contains(query);
    }).take(5).toList();

    setState(() {
      _suggestions = matches;
    });
  }

  void _onSuggestionTap(Establishment establishment) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InspectionFormScreen(establishment: establishment),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Start New Inspection',
              style: widget.theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Search by Establishment Name, ID, or scan a QR code.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Search Establishment...',
                prefixIcon: Icon(Icons.search, color: widget.theme.colorScheme.primary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          _searchFocusNode.unfocus();
                        })
                    : null,
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
            ),
            if (_suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(20),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final est = _suggestions[index];
                    return ListTile(
                      title: Text(est.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('ID: ${est.id} • ${est.category}'),
                      onTap: () => _onSuggestionTap(est),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            ..._suggestions.isEmpty
                ? [
                    Center(
                      child: Text(
                        'OR',
                        style: TextStyle(
                            color: Colors.grey.shade400,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const QRScannerScreen()),
                          );
                        },
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan QR Code'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.theme.colorScheme.primary,
                          side: BorderSide(color: widget.theme.colorScheme.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const AddEstablishmentScreen()),
                          );
                        },
                        child: const Text('Add New Establishment Manually'),
                      ),
                    ),
                  ]
                : [],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
