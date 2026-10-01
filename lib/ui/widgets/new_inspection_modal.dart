import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../data/models/establishment.dart';
import '../../data/services/offline_service.dart';
import '../../core/theme/app_theme.dart';

// [REF: NEW_INSPECTION_MODAL]
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

  // [REF: MODAL_ESTABLISHMENT_SEARCH]
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
    context.pop();
    context.push('/inspection', extra: establishment);
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
        top: 12,
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
            // Modal Handle
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Start New Inspection',
              style: TextStyle(
                fontFamily: '.SF Pro Display',
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Search by Establishment Name, ID, or scan a QR code.',
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: const TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search Establishment...',
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                prefixIcon: Icon(CupertinoIcons.search, color: widget.theme.colorScheme.primary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(CupertinoIcons.clear_thick_circled, color: AppTheme.textSecondary, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _searchFocusNode.unfocus();
                        })
                    : null,
                filled: true,
                fillColor: AppTheme.background,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: widget.theme.colorScheme.primary, width: 1.5),
                ),
              ),
            ),
            if (_suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 12),
                constraints: const BoxConstraints(maxHeight: 250),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: AppTheme.softShadow,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) {
                    final est = _suggestions[index];
                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.storefront_rounded, color: AppTheme.textSecondary, size: 20),
                        ),
                        title: Text(
                          est.name,
                          style: const TextStyle(
                            fontFamily: '.SF Pro Display',
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        // Owner name is what an inspector uses to tell two
                        // similarly named businesses apart. The fallback is
                        // insurance, not an observed case: no live record has
                        // a blank owner today, but the web admin's form makes
                        // the field optional (it stores null for an empty
                        // one), so an empty subtitle is reachable.
                        subtitle: Text(
                          est.ownerName.isNotEmpty ? est.ownerName : est.formattedAddress,
                          style: const TextStyle(
                            fontFamily: '.SF Pro Text',
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _onSuggestionTap(est),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 24),
            // Show 'no results' hint only when a query has been typed but nothing matched
            if (_searchController.text.isNotEmpty && _suggestions.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    const Icon(Icons.search_off_rounded, color: AppTheme.textSecondary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No establishments found for "${_searchController.text}".',
                        style: const TextStyle(
                          fontFamily: '.SF Pro Text',
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ..._suggestions.isEmpty
                ? [
                    const Row(
                      children: [
                        Expanded(child: Divider(color: AppTheme.border)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'OR',
                            style: TextStyle(
                              fontFamily: '.SF Pro Text',
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: AppTheme.border)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          context.pop();
                          context.push('/qr');
                        },
                        icon: const Icon(CupertinoIcons.qrcode_viewfinder),
                        label: const Text('Scan QR Code'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.theme.colorScheme.primary,
                          side: BorderSide(color: widget.theme.colorScheme.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: '.SF Pro Display',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
